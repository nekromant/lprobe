#define LUA_LIB
#define _GNU_SOURCE 

#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdint.h>
#include <lua.h>
#include <lauxlib.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <linux/lprobe.h>
#include <poll.h>

#define panic() { exit(1); }
#define require_args(nargs, n)						\
	if (nargs != n)							\
		return luaL_error(L, "Invalid arg count to %s (need %d but got %d)", __func__, n, nargs);


void lua_stack_dump (lua_State *L)
{
	int i=lua_gettop(L);
	printf(" ----------------  Stack Dump ----------------\n" );
	while(  i   ) {
		int t = lua_type(L, i);
		switch (t) {
		case LUA_TSTRING:
			printf("%d:`%s'\n", i, lua_tostring(L, i));
			break;
		case LUA_TBOOLEAN:
			printf("%d: %s\n",i,lua_toboolean(L, i) ? "true" : "false");
			break;
		case LUA_TNUMBER:
			printf("%d: %g\n",  i, lua_tonumber(L, i));
			break;
		default: printf("%d: %s\n", i, lua_typename(L, t)); break;
		}
		i--;
	}
	printf("--------------- Stack Dump Finished ---------------\n" );
}


const char *lp_get_stringfield (lua_State *L, const char *key) {
	const char *result;

	lua_pushstring(L, key);
	lua_gettable(L, -2);
	result = lua_tostring(L, -1);
	lua_pop(L, 1);  /* remove number */
	return result;
}

int lp_get_numberfield (lua_State *L, const char *key) {
	int result;
	lua_pushstring(L, key);
	lua_gettable(L, -2);
	if (!lua_isnumber(L, -1))
		return luaL_error(L, "invalid key");
	result = lua_tonumber(L, -1);
	lua_pop(L, 1);  /* remove number */
	return result;
}



/* reread stats from dev file */
static int l_refresh(lua_State *L)
{

	int nargs = lua_gettop(L);
	require_args(nargs, 2);

	if ((!lua_istable(L,-1))) 
		return luaL_error(L, "Invalid args to l_refresh");	

	const char *path = lp_get_stringfield(L, "device");
	if (!path) 
		return luaL_error(L, "fatal: missing 'device' in device instance table");
	
	int fd = lp_get_numberfield(L, "fd");
	
	int ret = ioctl(fd, IOCTL_LPROBE_REFRESH, NULL);
        if (ret != 0) 
		luaL_error(L, "ioctl: %s", strerror(errno));
	
	lua_pushstring(L, "info");

	int status = luaL_loadfile(L, path);
	if (status)
		luaL_error(L, "Fatal error while loading device file: %s\n", lua_tostring(L, -1));
	
	status = lua_pcall(L, 0, 1, 0);
	if (status)
		luaL_error(L, "Fatal error while running device file: %s\n", lua_tostring(L, -1));

	lua_settable(L, -3);
	
	return 0;
}



static int l_open (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 1);
	
	const char* devname = lua_tostring(L, -1);  
	
	int fd = open(devname, O_RDWR);
	if (fd < 0) 
		return luaL_error(L, "Failed to open: %s err %d", devname, errno);
	
	lua_newtable(L);

	lua_pushstring(L, "fd");
	lua_pushnumber(L, fd);
	lua_settable(L, -3);

	lua_pushstring(L, "device");
	lua_pushstring(L, devname);
	lua_settable(L, -3);

	l_refresh(L);

	return 1;
}

/* fd, mmapid, length */
static int l_request_mem (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 3);
	
	int fd     = lua_tonumber(L, 1); 
	int mmapid = lua_tonumber(L, 2); 
	int length = lua_tonumber(L, 3);

	void *ptr = mmap(NULL, length,  PROT_READ | PROT_WRITE, MAP_SHARED, fd, 
			 mmapid * getpagesize());	
	if (ptr == ((void *) -1))
		return luaL_error(L, "Failed to mmap memory: mmapid %d len %d", mmapid, length);
	lua_pushlightuserdata(L, ptr);
	return 1;
}

/* ptr/userdata, offset, type */
static int l_read (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 3);

	uint8_t *mmapmem = lua_touserdata(L, 1); 
	int offset    = lua_tonumber(L, 2);
	int type      = lua_tonumber(L, 3);

	mmapmem = &mmapmem[offset];
	
	uint16_t *mmap16 = (uint16_t *) mmapmem; 
	uint32_t *mmap32 = (uint32_t *) mmapmem; 
	uint64_t *mmap64 = (uint64_t *) mmapmem; 

	int8_t  *mmap8s  = (int8_t  *) mmapmem; 
	int16_t *mmap16s = (int16_t *) mmapmem; 
	int32_t *mmap32s = (int32_t *) mmapmem; 
	int64_t *mmap64s = (int64_t *) mmapmem; 

	if ((type < 10) && (offset % type)) 
		luaL_error(L, "l_read: read not aligned!\n");

	if ((type > 10) && ((offset % (type - 10)))) 
		luaL_error(L, "l_read: read not aligned!\n");
	
	switch (type) { 
	case 1:
		lua_pushnumber(L, *mmapmem);
		break;
	case 2:
		lua_pushnumber(L, *mmap16);
		break;
	case 4:
		lua_pushnumber(L, *mmap32);
		break;		
	case 8:
		lua_pushnumber(L, *mmap64);
		break;
	case 11:
		lua_pushnumber(L, *mmap8s);
		break;
	case 12:
		lua_pushnumber(L, *mmap16s);
		break;
	case 14:
		lua_pushnumber(L, *mmap32s);
		break;		
	case 18:
		lua_pushnumber(L, *mmap64s);
		break;		
	default:
		return luaL_error(L, "Invalid IO type for l_read");
		break;

	}
	return 1;
}

/* fd, irq */
static int l_irq_ack (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 2);

	int fd     = lua_tonumber(L, 1);
	int irqnum = lua_tonumber(L, 2);
	int ret = ioctl(fd, IOCTL_LPROBE_IRQACK, &irqnum);
        if (ret != 0) 
		luaL_error(L, "ioctl: %s", strerror(errno));
	return 0;
}


/* fd, number of irqs */
static int l_irq_pending (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 1);

	int fd       = lua_tonumber(L, 1);	
	uint32_t flags;
	int ret = ioctl(fd, IOCTL_LPROBE_IRQGETPENDING, &flags);
        if (ret != 0) 
		luaL_error(L, "ioctl: %s", strerror(errno));
	int i; 
	int total=0;
	for (i=0; i< 32; i++)
		if (flags & (1 << i)) {
			lua_pushnumber(L, i);
			total++;
		}
	return total;
}

/* fd, timeout_ms */
static int l_irq_wait (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 2);
	
	int fd      = lua_tonumber(L, 1);
	int timeout = lua_tonumber(L, 2);

	struct pollfd pfd;
	pfd.fd = fd;
	pfd.events = POLLIN;
	int ret = poll(&pfd, 1, timeout);
	if (ret < 0) 
		return luaL_error(L, "poll() failed");
	lua_pushboolean(L, ret ? 1 : 0);
	return 1;
}

/* ptr/userdata, offset, type, value */
static int l_write (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 4);

	uint8_t *mmapmem = lua_touserdata(L, 1); 
	int offset    = lua_tonumber(L, 2);
	if (offset < 0) 
		return luaL_error(L, "Negative offset to l_write");

	int type      = lua_tonumber(L, 3);
	mmapmem = &mmapmem[offset];
	
	uint16_t *mmap16 = (uint16_t *) mmapmem; 
	uint32_t *mmap32 = (uint32_t *) mmapmem; 
	uint64_t *mmap64 = (uint64_t *) mmapmem; 

	int8_t  *mmap8s  = (int8_t  *)  mmapmem; 
	int16_t *mmap16s = (int16_t *)  mmapmem; 
	int32_t *mmap32s = (int32_t *)  mmapmem; 
	int64_t *mmap64s = (int64_t *)  mmapmem; 

	if ((type < 10) && (offset % type)) 
		luaL_error(L, "l_write: read not aligned!\n");
	else if ((type > 10) && ((offset % (type - 10)))) 
		luaL_error(L, "l_write: read not aligned!\n");
	
	switch (type) { 
	case 1:
		*mmapmem = lua_tonumber(L, 4);
		break;
	case 2:
		*mmap16 = lua_tonumber(L, 4);
		break;
	case 4:
		*mmap32 = lua_tonumber(L, 4);
		break;		
	case 8:
		*mmap64 = lua_tonumber(L, 4);
		break;		
	case 10:
		*mmap8s = lua_tonumber(L, 4);
		break;
	case 12:
		*mmap16s = lua_tonumber(L, 4);
		break;
	case 14:
		*mmap32s = lua_tonumber(L, 4);
		break;		
	case 18:
		*mmap64s = lua_tonumber(L, 4);
		break;		
	default:
		return luaL_error(L, "Invalid IO type for l_write");
		break;
	}

	return 0;
}

static int l_read_from_file (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 4);

	uint8_t *mmapmem = lua_touserdata(L, 1); 
	int offset       = lua_tonumber(L, 2);
	int len          = lua_tonumber(L, 3);
	const char* fl   = lua_tostring(L, 4);
	mmapmem = &mmapmem[offset];
	
	FILE *fd = fopen(fl, "r");
	if (!fd)
		return luaL_error(L, "Failed to open file: %s", fl);
	int ret = fread(mmapmem, len, 1, fd);
	lua_pushboolean(L, ret);
	fclose(fd);
	return 1;
}

static int l_write_to_file (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 4);

	uint8_t *mmapmem = lua_touserdata(L, 1); 
	int offset       = lua_tonumber(L, 2);
	int len          = lua_tonumber(L, 3);
	const char* fl   = lua_tostring(L, 4);
	mmapmem = &mmapmem[offset];
	
	FILE *fd = fopen(fl, "w");
	if (!fd)
		return luaL_error(L, "Failed to open file: %s", fl);
	int ret = fwrite(mmapmem, len, 1, fd);
	lua_pushboolean(L, ret);
	fclose(fd);
	return 1;
}


static int l_pagesize (lua_State *L) 
{
	lua_pushnumber(L, getpagesize());
	return 1;
}

static int l_memcmp (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 4);

	uint8_t *mmapmem1 = lua_touserdata(L, 1); 
	uint8_t *mmapmem2 = lua_touserdata(L, 2); 
	int offset       = lua_tonumber(L, 3);
	int len          = lua_tonumber(L, 4);
	int ret = memcmp(&mmapmem1[offset], &mmapmem2[offset], len);
	lua_pushnumber(L, ret);
	return 1;
}

static int l_memset (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 4);
	uint8_t *mmapmem1 = lua_touserdata(L, 1); 
	int off           = lua_tonumber(L, 2);
	int c             = lua_tonumber(L, 3);
	int len           = lua_tonumber(L, 4);
	memset(&mmapmem1[off], c, len);
	return 0;
}

static int l_random (lua_State *L) 
{
	int nargs = lua_gettop(L);
	require_args(nargs, 3);
	uint8_t *mmapmem  = lua_touserdata(L, 1); 
	int off           = lua_tonumber(L, 2);
	int len           = lua_tonumber(L, 3);

	int fd = open("/dev/urandom", O_RDONLY);
	if (!fd)
		return luaL_error(L, "Failed to open /dev/urandom");
	int ret = read(fd, &mmapmem[off], len);
	lua_pushboolean(L, ret);
	close(fd);
	return 1;
}

static struct timeval	tv, tv0;
static int l_get_uptime_ms(lua_State *L) 
{
	gettimeofday(&tv, NULL);
	float v = (tv.tv_sec-tv0.tv_sec) + 0.000001*((float)(tv.tv_usec-tv0.tv_usec));
	lua_pushnumber(L, v);
	return 1;
}

static const luaL_Reg libfuncs[] = {
        {"open",           l_open},
        {"refresh",        l_refresh},
        {"request_mem",    l_request_mem},

        {"write",          l_write},
        {"read",           l_read},

	{"write_to_file",  l_write_to_file},
	{"read_from_file", l_read_from_file},

	{"irq_ack",        l_irq_ack},
	{"irq_pending",    l_irq_pending},
	{"irq_wait",       l_irq_wait},

	{"uptime_ms",      l_get_uptime_ms},
	{"pagesize",       l_pagesize},
	{"memcmp",         l_memcmp}, //optional
	{"memset",         l_memset}, //optional
	{"random",         l_random}, //optional
        {NULL,             NULL}
};

LUALIB_API int luaopen_lprobelnx (lua_State *L) 
{
	printf("L-Probe/Linux 0.1: Loaded!\n");
	luaL_newlib(L, libfuncs);
	gettimeofday(&tv0, NULL);
	return 1;
}

-include blackjack.mk

MAKEFLAGS += --no-builtin-rules

.SUFFIXES:


define PKG_CONFIG
CFLAGS  += $$(shell pkg-config --cflags  $(1))
LDFLAGS += $$(shell pkg-config --libs $(1))
endef

CFLAGS+=-Iinclude/ -I../linux/include/uapi/ -fPIC -Wall -g

DEBUG=y

ifeq ($(DEBUG),y)
CFLAGS+=-g -DDEBUG_LEVEL=4
else
CFLAGS+=-DDEBUG_LEVEL=0
endif

$(eval $(call PKG_CONFIG,lua5.2))

obj-y+=lprobe-linux.o

%.o: %.c 
	$(SILENT_CC)$(CROSS_COMPILE)gcc $(CFLAGS) -c -o $(@) $(<)

liblprobelnx.so: $(obj-y)
	$(SILENT_LD)$(CROSS_COMPILE)gcc -O -shared -fpic -o $(@) $(^) $(LDFLAGS) 

clean: 
	rm *.o *.so

emc:
	emc *.c include/*.h


scripts:= lua/adma.lua \
	  lua/lprobe-memory.lua \
	  lua/lprobe-device.lua \
	  lua/fiberchannel.lua \
	  lua/adma-table.lua

doc: $(scripts)
	luadoc -d doc/ $(^)
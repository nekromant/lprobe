lprobe
======

lprobe - Универсальный драйвер для ПЛИС-прототипирования с использованием скриптового языка lua. 


Подключение
===========


В devicetree файле, в узле отвечающем за устройство необходимо указать lprobe как совместимый
драйвер. Пример: 


fpga_fiberchannel: fpga_fiberchannel@40000000 {
	compatible = "rcm,lprobe";
	reg = <0x40000000 0x1000>;
	reg-names = "registers";
	device-name = "fiber";
	interrupt-parent = <&ps7_scugic_0>;
	interrupts = <0 29 4>, <0 30 4>;
	interrupt-names = "frontend", "dma";
	dma-pool-count=<3>; 
	dma-pools = <0x1000>, <0x1000>, <0x10000>;
	dma-pool-names = "rx", "tx", "data";
};

device-name - название устройства. Его можно будет использовать как аргумент для lprobe:open() вместо пути к устройству

reg - регистры устройства. 
reg-names - имена регистров устройства. Имена используются как идентификаторы при lpobe:request_mem 

interrupt-parent, interrupt-names, interrupts - прерывания устройства. Имена используются как идентификаторы при вызове lprobe:request_irq

dma-pool-count - количество областей непрерывно некешируемой памяти для DMA
pma-pools - массив состоящий из желаемого размера областей для dma. 
pma-pool-names - имена-идентификаторы для областей памяти. Используются при вызове lprobe:request_mem


Использование
================

Для начала работы необходимо подключить библиотеку языка lua lprobe. 

lp = require("lprobe"); 

Работа с памятью и регистрами. 
==============================

Области памяти для dma/регистров можно получить через

mem = lp:request_mem("id");

на 

CC = gcc
COPTS = -O3

.PHONY: all
all: iq_server iq_client iq_fm

iq_base: iq_base.c
	$(CC) $(COPTS) -o iq_base.o -lm

iq_server: iq_server.c iq_base.o
	$(CC) $(COPTS) -o iq_server iq_server.c iq_base.o -lm -pthread

iq_client: iq_client.c
	$(CC) $(COPTS) -o iq_client iq_client.c -lm

iq_fm: iq_fm.c
	$(CC) $(COPTS) -o iq_fm iq_fm.c -lm



.PHONY: clean
clean:
	rm -f iq_server iq_client iq_fm
	rm -f iq_base.o


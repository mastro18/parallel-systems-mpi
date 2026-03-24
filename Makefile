CC = mpicc
CFLAGS = -g -O2 -Wall

all: 3_1 3_2

3_1: 3_1.c
	$(CC) $(CFLAGS) -o 3_1 3_1.c

3_2: 3_2.c
	$(CC) $(CFLAGS) -o 3_2 3_2.c

clean:
	rm -f 3_1 3_2

.PHONY: all clean

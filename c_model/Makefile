CC = gcc
CFLAGS = -g -Wall
SRCS = conv.c max_pool.c init.c main.c
OBJS = $(SRCS:.c=.o)

all: lenet pad

lenet: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

pad: pad.c
	$(CC) $(CFLAGS) -o $@ $?

%.o: %.c
	$(CC) $(CFLAGS) -c $?

clean:
	-rm lenet pad *.o

.PHONY: clean

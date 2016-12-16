CC = gcc
CFLAGS = -g -Wall
SRCS = conv.c max_pool.c init.c main.c
OBJS = $(SRCS:.c=.o)

lenet: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) -c $?

clean:
	-rm lenet *.o

.PHONY: clean

CC = gcc
CFLAGS = -g -Wall
SRCS = conv.c max_pool.c init.c main.c
OBJS = $(SRCS:.c=.o)

all: lenet pad_knl pad_img

lenet: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

pad_knl: pad_knl.c
	$(CC) $(CFLAGS) -o $@ $?

pad_img: pad_img.c
	$(CC) $(CFLAGS) -o $@ $?

%.o: %.c
	$(CC) $(CFLAGS) -c $?

clean:
	-rm lenet pad_knl pad_img *.o

.PHONY: clean

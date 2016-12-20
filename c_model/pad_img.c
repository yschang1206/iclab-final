/**
 * pad_img.c
 */
#include <stdio.h>
#include <stdlib.h>
#define FMAP_WIDTH 32
#define FMAP_HEIGHT 32
#define FMAP_DEPTH 16

int mem_addr = 0;

void add_pad(int n, FILE *fp)
{
    mem_addr += n;
    fprintf(fp, "@%x\n", mem_addr);
}

int main(int argc, char *argv[])
{
    char buf[16];
    FILE *fp_in, *fp_out;
    int width, height;
    int cur_width = 0, cur_height = 0;

    if (argc != 6) {
        fprintf(stderr, "usage: ./pad_img input_file output_file w h base_addr\n");
        exit(1);
    }

    fp_in = fopen(argv[1], "r");
    if (fp_in == NULL) {
        fprintf(stderr, "can't open %s\n", argv[1]);
        exit(1);
    }

    fp_out = fopen(argv[2], "w");
    if (fp_out == NULL) {
        fprintf(stderr, "can't open %s\n", argv[2]);
        exit(1);
    }

    width = atoi(argv[3]);
    height = atoi(argv[4]);
    mem_addr = atoi(argv[5]);
    fprintf(fp_out, "@%x\n", mem_addr);
    while (fgets(buf, 16, fp_in) != NULL) {
        mem_addr++;
        fputs(buf, fp_out);
        cur_width++;
        if (cur_width == width) {
            add_pad(FMAP_WIDTH - width, fp_out);
            cur_width = 0;
            cur_height++;
            if (cur_height == height) {
                add_pad((FMAP_HEIGHT - height) * FMAP_WIDTH, fp_out);
                cur_height = 0;
            }
        }
    }

    return 0;
}

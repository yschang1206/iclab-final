/**
 * pad_knl.c
 */
#include <stdio.h>
#include <stdlib.h>
#define KNL_AREA 32
#define KNL_DEPTH 16
#define KNL_NUM 16

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
    int area, depth;
    int cur_area = 0, cur_depth = 0;

    if (argc != 5) {
        fprintf(stderr, "usage: ./pad_knl input_file output_file d base_addr\n");
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

    area = 25;
    depth = atoi(argv[3]);
    mem_addr = atoi(argv[4]);
    fprintf(fp_out, "@%x\n", mem_addr);
    while (fgets(buf, 16, fp_in) != NULL) {
        mem_addr++;
        fputs(buf, fp_out);
        cur_area++;
        if (cur_area == area) {
            add_pad(KNL_AREA - area, fp_out);
            cur_area = 0;
            cur_depth++;
            if (cur_depth == depth) {
                add_pad((KNL_DEPTH - depth) * KNL_AREA, fp_out);
                cur_depth = 0;
            }
        }
    }

    return 0;
}

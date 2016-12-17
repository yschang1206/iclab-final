/**
 * pad.c
 */
#include <stdio.h>
#include <stdlib.h>
#define KNL_AREA 32
#define KNL_DEPTH 16
#define KNL_NUM 16

void add_pad(int n, FILE *fp)
{
    int i;

    for (i = 0; i < n; i++) {
        fprintf(fp, "0000_0000\n");
    }
}

int main(int argc, char *argv[])
{
    char buf[16];
    FILE *fp_in, *fp_out;
    int area, depth, num;
    int cur_area = 0, cur_depth = 0, cur_num = 0;

    if (argc != 7) {
        fprintf(stderr, "usage: ./pad input_file output_file w h d n\n");
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

    area = atoi(argv[3]) * atoi(argv[4]);
    depth = atoi(argv[5]);
    num = atoi(argv[6]);
    while (fgets(buf, 16, fp_in) != NULL) {
        fputs(buf, fp_out);
        cur_area++;
        if (cur_area == area) {
            add_pad(KNL_AREA - area, fp_out);
            cur_area = 0;
            cur_depth++;
            if (cur_depth == depth) {
                add_pad((KNL_DEPTH - depth) * KNL_AREA, fp_out);
                cur_depth = 0;
                cur_num++;
                if (cur_num == num) {
                    add_pad((KNL_NUM - num) * KNL_AREA * KNL_DEPTH, fp_out);
                    cur_num = 0;
                }
            }
        }
    }

    return 0;
}

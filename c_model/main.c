/**
 * main.c
 */

#include "includes.h"

void print_readmemh_format(int32_t n, FILE *fp)
{
    uint8_t *tmp = (uint8_t *)&n;

    fprintf(fp, "%.2x%.2x_%.2x%.2x\n", tmp[3], tmp[2], tmp[1], tmp[0]);
}

void print_fmap_size(int layer, fmap_t *fmap)
{
    printf("***** Layer %d *****\n", layer);
    printf("w: %d\n", fmap->w);
    printf("h: %d\n", fmap->h);
    printf("d: %d\n", fmap->d);
}

void print_knl_data(kernel_t *knls, int num_knl, int layer)
{
    int i, j, k, l;
    int p;
    kernel_t *knl;
    FILE *fp_wt, *fp_bs;
    char fname_wt[64], fname_bs[64];

    sprintf(fname_wt, "../data/l%d.wt.unpad", layer);
    sprintf(fname_bs, "../data/l%d.bs.unpad", layer);
    fp_wt = fopen(fname_wt, "w");
    if (fp_wt == NULL) {
        fprintf(stderr, "fail opening ../data/weights.dat.unpad\n");
        exit(1);
    }
    fp_bs = fopen(fname_bs, "w");
    if (fp_bs == NULL) {
        fprintf(stderr, "fail opening ../data/biases.dat.unpad\n");
        exit(1);
    }
    for (i = 0; i < num_knl; i++) {
        knl = &knls[i];
        print_readmemh_format(knl->bias, fp_bs);
        for (j = 0; j < knl->d; j++)
            for (k = 0; k < knl->h; k++)
                for (l = 0; l < knl->w; l++) {
                    p = DT_3TO1(l, k, j, knl->w, knl->h);
                    print_readmemh_format(knl->weights[p], fp_wt);
                }
    }
    fclose(fp_wt);
    fclose(fp_bs);
}

void print_fmap_data(fmap_t *fmap, char *fname)
{
    int i, j, k;
    int p;
    FILE *fp;

    fp = fopen(fname, "w");
    if (fp == NULL) {
        fprintf(stderr, "fail opening %s\n", fname);
        exit(1);
    }
    for (i = 0; i < fmap->d; i++)
        for (j = 0; j < fmap->h; j++)
            for (k = 0; k < fmap->w; k++) {
                p = DT_3TO1(k, j, i, fmap->w, fmap->h);
                print_readmemh_format(fmap->data[p], fp);
            }
    fclose(fp);
}

void print_result(fmap_t *fmap)
{
    int i;

    for (i = 0; i < fmap->d; i++)
        printf("%d: %d\n", i, fmap->data[i]);
}

int main(int argc, char *argv[])
{
    kernel_t *knls;
    fmap_t *ifmap, *ofmap;
    int w_knl, w_fmap, h_knl, h_fmap, d, n, l;

    if (argc != 2) {
        fprintf(stderr, "usage: ./lenet img_file\n");
        return 1;
    }

    #define O 1
    #define X 0
    static const int tbl[] = { 
        O, X, X, X, O, O, O, X, X, O, O, O, O, X, O, O,
        O, O, X, X, X, O, O, O, X, X, O, O, O, O, X, O,
        O, O, O, X, X, X, O, O, O, X, X, O, X, O, O, O,
        X, O, O, O, X, X, O, O, O, O, X, X, O, X, O, O,
        X, X, O, O, O, X, X, O, O, O, O, X, O, O, X, O,
        X, X, X, O, O, O, X, X, O, O, O, O, X, O, O, O
    };
    #undef O
    #undef X

    /* layer 0: convolution */
    w_knl = 5;
    w_fmap = 32;
    h_knl = 5;
    h_fmap = 32;
    d = 1;
    n = 6;
    l = 0;
    /* initialize kernels and image data */
    knls = init_kernels(w_knl, h_knl, d, n, l);
    print_knl_data(knls, n, l);
    ifmap = init_fmap(w_fmap, h_fmap, d);
    load_img(ifmap, argv[1], w_fmap, h_fmap);
    print_fmap_data(ifmap, "../data/img.dat.unpad");
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out0.dat.unpad");

    /* layer 1: max pooling */
    /* maxpooling layer */
    ofmap = max_pool(ifmap);
    /* free obsolete objects */
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out1.dat.unpad");

    /* layer 2: convolution */
    w_knl = 5;
    w_fmap = ifmap->w;
    h_knl = 5;
    h_fmap = ifmap->h;
    d = ifmap->d;
    n = 16;
    l = 2;
    /* initialize kernels */
    knls = init_kernels(w_knl, h_knl, d, n, l);
    print_knl_data(knls, n, l);
    /* convolution layer */
    ofmap = conv_tbl(knls, ifmap, n, tbl);
    //ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out2.dat.unpad");

    /* layer 3: max pooling */
    /* maxpooling layer */
    ofmap = max_pool(ifmap);
    /* free obsolete objects */
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out3.dat.unpad");

    /* layer 4: fully-connected */
    w_knl = ifmap->w;
    w_fmap = ifmap->w;
    h_knl = ifmap->h;
    h_fmap = ifmap->h;
    d = ifmap->d;
    n = 120;
    l = 4;
    /* initialize kernels */
    knls = init_kernels(w_knl, h_knl, d, n, l);
    print_knl_data(knls, n, l);
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out4.dat.unpad");

    /* layer 5: fully-connected */
    w_knl = ifmap->w;
    w_fmap = ifmap->w;
    h_knl = ifmap->h;
    h_fmap = ifmap->h;
    d = ifmap->d;
    n = 10;
    l = 5;
    /* initialize kernels */
    knls = init_kernels_fc(w_knl, h_knl, d, n, l);
    print_knl_data(knls, n, l);
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    print_fmap_data(ofmap, "../data/out5.dat.unpad");

    print_result(ofmap);

    return 0;
}

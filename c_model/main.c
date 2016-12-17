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

void print_knl_data(kernel_t *knls, int num_knl)
{
    int i, j, k, l;
    int p;
    kernel_t *knl;
    FILE *fp;

    fp = fopen("../data/weights.dat", "w");
    if (fp == NULL) {
        fprintf(stderr, "fail opening ../data/weights.dat\n");
        exit(1);
    }
    for (i = 0; i < num_knl; i++) {
        knl = &knls[i];
        for (j = 0; j < knl->d; j++)
            for (k = 0; k < knl->h; k++)
                for (l = 0; l < knl->w; l++) {
                    p = DT_3TO1(l, k, j, knl->w, knl->h);
                    print_readmemh_format(knl->weights[p], fp);
                }
    }
    fclose(fp);
}

void print_fmap_data(fmap_t *fmap)
{
    int i, j, k;

    for (i = 0; i < fmap->d; i++)
        for (j = 0; j < fmap->h; j++)
            for (k = 0; k < fmap->w; k++) {
                printf("%d, ", fmap->data[DT_3TO1(k, j, i, fmap->w, fmap->h)]);
            }
    printf("\n");
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
    print_knl_data(knls, n);
    ifmap = init_fmap(w_fmap, h_fmap, d);
    //print_fmap_size(0, ifmap);
    load_img(ifmap, argv[1], w_fmap, h_fmap);
    //print_fmap_data(ifmap);
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(1, ofmap);
    //print_fmap_data(ofmap);

    /* layer 1: max pooling */
    /* maxpooling layer */
    ofmap = max_pool(ifmap);
    /* free obsolete objects */
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(2, ofmap);
    //print_fmap_data(ofmap);

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
    /* convolution layer */
    ofmap = conv_tbl(knls, ifmap, n, tbl);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(3, ofmap);
    //print_fmap_data(ofmap);

    /* layer 3: max pooling */
    /* maxpooling layer */
    ofmap = max_pool(ifmap);
    /* free obsolete objects */
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(4, ofmap);
    //print_fmap_data(ofmap);

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
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(5, ofmap);
    //print_fmap_data(ofmap);

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
    /* convolution layer */
    ofmap = conv(knls, ifmap, n);
    /* free obsolete objects */
    free_kernels(knls, n);
    free_fmap(ifmap);
    ifmap = ofmap;
    //print_fmap_size(6, ofmap);
    //print_fmap_data(ofmap);

    print_result(ofmap);

    return 0;
}

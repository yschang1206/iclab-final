/**
 * conv.c
 */
#include "includes.h"

/* internal functions */
void conv_one_pixel(int x, int y, int n, kernel_t *knls, fmap_t *ifmap, fmap_t *ofmap)
{
    int i, j, k;
    int p = DIM_OUT(x, y, n, ofmap->w, ofmap->h);
    kernel_t *knl;
    int32_t product;

    knl = &(knls[n]);
    ofmap->data[p] = 0;
    for (i = 0; i < knl->d; i++)
        for (j = 0; j < knl->h; j++)
            for (k = 0; k < knl->w; k++) {
                product = knl->weights[DIM_KNL(k, j, i, knl->w, knl->h)] * \
                    ifmap->data[DIM_IN(k + x, j + y, i, ifmap->w, ifmap->h)];
                //ofmap->data[p] += (product / ROUND_OFF);
                ofmap->data[p] += (product >> 16);
            }
    ofmap->data[p] += knl->bias;
    /* relu */
    if (ofmap->data[p] < 0)
        ofmap->data[p] = 0;
}

void conv_one_pixel_tbl(int x, int y, int n, kernel_t *knls, fmap_t *ifmap, fmap_t *ofmap, const int *tbl, int num_knl)
{
    int i, j, k;
    int p = DIM_OUT(x, y, n, ofmap->w, ofmap->h);
    kernel_t *knl;
    int32_t product;

    knl = &(knls[n]);
    ofmap->data[p] = 0;
    for (i = 0; i < knl->d; i++) {
        if (!tbl[n + i * num_knl]) {
            //printf("id: %d, od: %d\n", i, n);
            continue;
        }
        for (j = 0; j < knl->h; j++)
            for (k = 0; k < knl->w; k++) {
                product = knl->weights[DIM_KNL(k, j, i, knl->w, knl->h)] * \
                    ifmap->data[DIM_IN(k + x, j + y, i, ifmap->w, ifmap->h)];
                //ofmap->data[p] += (product / ROUND_OFF);
                ofmap->data[p] += (product >> 16);
            }
    }
    ofmap->data[p] += knl->bias;
    /* relu */
    if (ofmap->data[p] < 0)
        ofmap->data[p] = 0;
}

fmap_t *conv(kernel_t *knls, fmap_t *ifmap, int num_knl)
{
    int i, j, k;
    int w, h, d;
    fmap_t *ofmap;

    /* calcuate metadata of output feature map */
    /* since every 3D-kernel has the same width and height, */ 
    /* we use the first one to calculate the size of the output feature map */
    w = ifmap->w - knls[0].w + 1;
    h = ifmap->h - knls[0].h + 1;
    d = num_knl;
    ofmap = init_fmap(w, h, d);

    /* calculate content of the output feature map */
    for (i = 0; i < d; i++)
        for (j = 0; j < h; j++)
            for (k = 0; k < w; k++)
                conv_one_pixel(k, j, i, knls, ifmap, ofmap);

    return ofmap;
}

fmap_t *conv_tbl(kernel_t *knls, fmap_t *ifmap, int num_knl, const int *tbl)
{
    int i, j, k;
    int w, h, d;
    fmap_t *ofmap;

    /* calcuate metadata of output feature map */
    /* since every 3D-kernel has the same width and height, */ 
    /* we use the first one to calculate the size of the output feature map */
    w = ifmap->w - knls[0].w + 1;
    h = ifmap->h - knls[0].h + 1;
    d = num_knl;
    ofmap = init_fmap(w, h, d);

    /* calculate content of the output feature map */
    for (i = 0; i < d; i++)
        for (j = 0; j < h; j++)
            for (k = 0; k < w; k++)
                conv_one_pixel_tbl(k, j, i, knls, ifmap, ofmap, tbl, num_knl);

    return ofmap;
}


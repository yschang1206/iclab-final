/**
 * max_pool.c
 */
#include "includes.h"

/* internal function */
int32_t find_max(int32_t *vals, int n)
{
    int i;
    int32_t max;

    max = vals[0];
    for (i = 1; i < n; i++)
        if (vals[i] > max)
            max = vals[i];

    return max;
}

fmap_t *max_pool(fmap_t *ifmap)
{
    int i, j, k;
    int w, h, d;
    int p;
    int32_t tmp[4];
    fmap_t *ofmap;

    w = ifmap->w / 2;
    h = ifmap->h / 2;
    d = ifmap->d;
    ofmap = init_fmap(w, h, d);

    for (i = 0; i < d; i++)
        for (j = 0; j < h; j++)
            for (k = 0; k < w; k++) {
                p = DT_3TO1(k, j, i, w, h);
                tmp[0] = ifmap->data[DT_3TO1(k * 2, j * 2, i, ifmap->w, ifmap->h)];
                tmp[1] = ifmap->data[DT_3TO1(k * 2 + 1, j * 2, i, ifmap->w, ifmap->h)];
                tmp[2] = ifmap->data[DT_3TO1(k * 2, j * 2 + 1, i, ifmap->w, ifmap->h)];
                tmp[3] = ifmap->data[DT_3TO1(k * 2 + 1, j * 2 + 1, i, ifmap->w, ifmap->h)];
                ofmap->data[p] = find_max(tmp, 4);
            }

    return ofmap;
}

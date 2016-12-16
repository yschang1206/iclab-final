/**
 * includes.h
 */

#ifndef INCLUDES_H_
#define INCLUDES_H_

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
/**
 * w: filter width
 * h: filter height
 * d: filter depth
 * weight: filter weights, size = w * h * d
 * biases: filter biases
 */
typedef struct {
    int w;
    int h;
    int d;
    int32_t *weights;
    int32_t bias;
} kernel_t;

/**
 * w: feature map width
 * h: feature map height
 * d: feature map depth
 * data: data of feature map, size = w * h * d
 */
typedef struct {
    int w;
    int h;
    int d;
    int32_t *data;
} fmap_t;

#define DIM_KNL(x, y, z, w, h) ((x) + (y) * (w) + (z) * (w) * (h))
#define DIM_IN(x, y, z, w, h) ((x) + (y) * (w) + (z) * (w) * (h))
#define DIM_OUT(x, y, n, w, h) ((x) + (y) * (w) + (n) * (w) * (h))
#define DT_3TO1(x, y, z, w, h) ((x) + (y) * (w) + (z) * (w) * (h))
#define AMP_RATIO 16384 // 2^16
#define ROUND_OFF 16384 // 2^16

kernel_t *init_kernels(int w, int h, int d, int n, int layer);
kernel_t *init_kernels_fc(int w, int h, int d, int n, int layer);
fmap_t *init_fmap(int w, int h, int d);
void load_img(fmap_t *fmap, char *fname_img, int w, int h);
void free_kernels(kernel_t *knls, int num_knl);
void free_fmap(fmap_t *fmap);
fmap_t *conv(kernel_t *knls, fmap_t *ifmap, int num_knl);
fmap_t *conv_tbl(kernel_t *knls, fmap_t *ifmap, int num_knl, const int *tbl);
fmap_t *max_pool(fmap_t *ifmap);

#endif  // INCLUDES_H

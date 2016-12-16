/**
 * init.h
 */
#include "includes.h"

kernel_t *init_kernels(int w, int h, int d, int n, int layer)
{
    FILE *fp_wt, *fp_bs;
    char fname_wt[20], fname_bs[20];
    kernel_t *knls;
    int i, j, k, l;
    float tmp;

    snprintf(fname_wt, 20, "../etc/layer%d.wt", layer);
    snprintf(fname_bs, 20, "../etc/layer%d.bs", layer);
    fp_wt = fopen(fname_wt, "r");
    if (fp_wt == NULL) {
        fprintf(stderr, "fail opening %s\n", fname_wt);
        exit(1);
    }
    fp_bs = fopen(fname_bs, "r");
    if (fp_bs == NULL) {
        fprintf(stderr, "fail opening %s\n", fname_bs);
        exit(1);
    }

    knls = (kernel_t *)malloc(sizeof(kernel_t) * n);
    for (i = 0; i < n; i ++) {
        knls[i].w = w;
        knls[i].h = h;
        knls[i].d = d;
        knls[i].weights = (int32_t *)malloc(sizeof(int32_t) * w * h * d);
        if (fscanf(fp_bs, "%f", &tmp) == EOF) {
            fprintf(stderr, "fail reading bias file\n");
            exit(1);
        }
        knls[i].bias = (int32_t)(tmp * AMP_RATIO);
    }

    for (i = 0; i < n; i++)
        for (j = 0; j < d; j++)
            for (k = 0; k < h; k++)
                for (l = 0; l < w; l++) {
                    //printf("%d %d %d %d\n", i, j, k ,l);
                    if (fscanf(fp_wt, "%f", &tmp) == EOF) {
                        fprintf(stderr, "fail reading weight file\n");
                        exit(1);
                    }
                    knls[i].weights[DT_3TO1(l, k, j, w, h)] = (int32_t)(tmp * AMP_RATIO);
                }

    fclose(fp_bs);
    fclose(fp_wt);

    return knls;
}

fmap_t *init_fmap(int w, int h, int d)
{
    fmap_t *fmap;

    fmap = (fmap_t *)malloc(sizeof(fmap));
    fmap->w = w;
    fmap->h = h;
    fmap->d = d;
    fmap->data = (int32_t *)calloc(w * h * d, sizeof(int32_t));

    return fmap;
}

void load_img(fmap_t *fmap, char *fname_img, int w, int h)
{
    FILE *fp;
    int i, j;
    int p;
    float tmp;

    fp = fopen(fname_img, "r");
    for (i = 0; i < h; i++)
        for (j = 0; j < w; j++) {
            p = DIM_IN(j, i, 0, w, h);
            fscanf(fp, "%f", &tmp);
            fmap->data[p] = (int32_t)(tmp * AMP_RATIO);
        }

    fclose(fp);
}

void free_kernels(kernel_t *knls, int num_knl)
{
    int i;

    for (i = 0; i < num_knl; i++)
        free(knls[i].weights);
    free(knls);
}

void free_fmap(fmap_t *fmap)
{
    free(fmap->data);
    free(fmap);
}

kernel_t *init_kernels_fc(int w, int h, int d, int n, int layer)
{
    FILE *fp_wt, *fp_bs;
    char fname_wt[20], fname_bs[20];
    kernel_t *knls;
    int i, j, k, l;
    float tmp;

    snprintf(fname_wt, 20, "../etc/layer%d.wt", layer);
    snprintf(fname_bs, 20, "../etc/layer%d.bs", layer);
    fp_wt = fopen(fname_wt, "r");
    if (fp_wt == NULL) {
        fprintf(stderr, "fail opening %s\n", fname_wt);
        exit(1);
    }
    fp_bs = fopen(fname_bs, "r");
    if (fp_bs == NULL) {
        fprintf(stderr, "fail opening %s\n", fname_bs);
        exit(1);
    }

    knls = (kernel_t *)malloc(sizeof(kernel_t) * n);
    for (i = 0; i < n; i ++) {
        knls[i].w = w;
        knls[i].h = h;
        knls[i].d = d;
        knls[i].weights = (int32_t *)malloc(sizeof(int32_t) * w * h * d);
        if (fscanf(fp_bs, "%f", &tmp) == EOF) {
            fprintf(stderr, "fail reading bias file\n");
            exit(1);
        }
        knls[i].bias = (int32_t)(tmp * AMP_RATIO);
    }

    for (j = 0; j < d; j++)
        for (i = 0; i < n; i++)
            for (k = 0; k < h; k++)
                for (l = 0; l < w; l++) {
                    //printf("%d %d %d %d\n", i, j, k ,l);
                    if (fscanf(fp_wt, "%f", &tmp) == EOF) {
                        fprintf(stderr, "fail reading weight file\n");
                        exit(1);
                    }
                    knls[i].weights[DT_3TO1(l, k, j, w, h)] = (int32_t)(tmp * AMP_RATIO);
                }

    fclose(fp_bs);
    fclose(fp_wt);

    return knls;
}


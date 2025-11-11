# DOE_02 vs DOE_03 Mann–Whitney U

Medians and two-sided Mann–Whitney U tests are computed from raw experiment_results.csv samples (n=90 per configuration).

## A_B_C_FULL

| Metric | Median DOE_02 | Median DOE_03 | U | z | p-value | Interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| Cache hit % | 22.49 | 22.57 | 3763.0 | -0.82 | 0.4116 | no sig shift |
| Bucket hit % | 59.54 | 59.46 | 3763.0 | -0.82 | 0.4116 | no sig shift |
| Cache hit latency (ns) | 33.00 | 33.00 | 3621.5 | -1.23 | 0.2202 | no sig shift |
| Bucket search latency (ns) | 55.00 | 55.00 | 3844.0 | -0.59 | 0.5556 | no sig shift |
| VM workload ns (q48) | 377.79e9 | 379.04e9 | 3722.0 | -0.94 | 0.3480 | no sig shift |

## A_B_CACHE

| Metric | Median DOE_02 | Median DOE_03 | U | z | p-value | Interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| Cache hit % | 17.27 | 17.31 | 3487.0 | -1.61 | 0.1072 | no sig shift |
| Bucket hit % | 64.76 | 64.72 | 3487.0 | -1.61 | 0.1072 | no sig shift |
| Cache hit latency (ns) | 29.00 | 29.00 | 3749.5 | -0.86 | 0.3899 | no sig shift |
| Bucket search latency (ns) | 51.00 | 50.00 | 3606.5 | -1.27 | 0.2045 | no sig shift |
| VM workload ns (q48) | 275.12e9 | 272.20e9 | 3439.0 | -1.75 | 0.0805 | trend (p<0.1) |

## A_BASELINE

| Metric | Median DOE_02 | Median DOE_03 | U | z | p-value | Interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| Cache hit % | 0.00 | 0.00 | 4050.0 | 0.00 | 1.0000 | no sig shift |
| Bucket hit % | 0.00 | 0.00 | 4050.0 | 0.00 | 1.0000 | no sig shift |
| Cache hit latency (ns) | 0.00 | 0.00 | 4050.0 | 0.00 | 1.0000 | no sig shift |
| Bucket search latency (ns) | 0.00 | 0.00 | 4050.0 | 0.00 | 1.0000 | no sig shift |
| VM workload ns (q48) | 263.49e9 | 268.14e9 | 3460.0 | -1.69 | 0.0914 | trend (p<0.1) |

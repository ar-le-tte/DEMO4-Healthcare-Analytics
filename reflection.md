# Reflection: OLTP vs Star Schema in Healthcare Analytics

## Why Is the Star Schema Faster?

The star schema significantly improves analytical performance compared to the normalized OLTP schema because it is designed specifically for read-heavy, aggregation-focused workloads.

In the OLTP model, even simple analytical questions required long join chains across many tables (encounters → providers → specialties → billing → diagnoses → procedures). These joins, combined with large `GROUP BY` operations and `COUNT(DISTINCT ...)`, caused queries to scale poorly as data volume increased.

In contrast, the star schema:
- Centers analysis on a single fact table (`fact_encounters`),
- Stores frequently used attributes (time, specialty, encounter type) as direct foreign keys,
- Pre-computes expensive metrics (billing totals, diagnosis/procedure counts) during ETL.

As a result, star schema queries require fewer joins, process fewer rows, and avoid repeated aggregations. This shift moves computational cost from query time to ETL time, which is more predictable and controllable.

---

## Join Comparison: OLTP vs Star Schema

| Query | OLTP Joins | Star Schema Joins |
|-----|-----------|------------------|
| Monthly encounters | 2–3 joins + aggregation | 3 lightweight joins |
| Diagnosis–procedure pairs | 4–5 joins + row explosion | 1 fact + 2 dimensions |
| 30-day readmissions | Self-join on encounters + providers + specialties | Indexed per-discharge lookup (LEFT JOIN LATERAL) on the fact table|
| Revenue by specialty | 4 joins + aggregation | 2 joins + pre-aggregated metrics |

The reduction in join depth is the single biggest reason for performance improvement.

---


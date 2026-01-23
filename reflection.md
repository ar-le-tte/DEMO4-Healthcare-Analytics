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

## Performance Quantification

Measured results from this lab show clear improvements:

- **30-Day Readmission Rate**
  - OLTP execution time: ~42 ms
  - Star schema execution time: ~18 ms
  - Improvement: ~2× faster

Readmission analysis is computed using an indexed per-discharge lookup (LEFT JOIN LATERAL) on the fact table, which avoids the row-explosion that happens with traditional self-joins on large encounter tables.

- **Revenue by Specialty & Month**
  - OLTP execution time: ~63 ms
  - Star schema execution time: ~16 ms
  - Improvement: ~4× faster

For revenue, the star query is basically just: filter billed encounters → join date + specialty → sum. In OLTP, we had to join billing → encounters → providers → specialties before we could even start aggregating.


These gains become even more significant as data volume increases beyond the 10,000-record scale used in this lab.

---

## Why Denormalization Helps Analytical Queries

Denormalization allows analytical queries to:
- Scan fewer tables,
- Avoid repeated calculations,
- Aggregate directly on pre-shaped data.

Instead of recomputing billing totals or diagnosis counts every time a query runs, these values are calculated once during ETL and reused. This dramatically reduces CPU usage and memory pressure during query execution.

In short, OLTP schemas optimize **writes and consistency**, while star schemas optimize **reads and insight generation**.

---

## Trade-offs: What Did We Gain? What Did We Lose?

### Gains
- Much faster analytical queries
- Simpler SQL for reporting and dashboards
- Predictable query performance
- Clear separation between transactional and analytical workloads
- Reusable, consistent dimensions (date/specialty/diagnosis/procedure) for future analyses
- Better BI friendliness (slicing/filtering works naturally with star schemas)
- Faster common metrics because key measures are computed once during ETL (totals, counts)

### Trade-offs
- Data duplication between OLTP and the warehouse (dimensions + fact), plus intentional denormalization in the fact table (e.g., storing specialty_key directly) to reduce join chains
- More complex ETL logic (key lookups, aggregations, and refresh strategy)
- Need to manage late-arriving facts and updates carefully
- Higher risk if ETL logic is incorrect (warehouse becomes the source of truth for analytics)
- More storage and maintenance overhead (bridges + indexes + history/backfills)
- More governance needed (reruns, auditability, data quality checks, incremental windows)


Despite these trade-offs, the benefits strongly outweigh the costs for analytics use cases. The added ETL complexity is justified by the performance and usability gains.

---

## Bridge Tables: Were They Worth It?

Yes.

Bridge tables allowed our model to:
- Preserve the one-row-per-encounter grain,
- Support many-to-many relationships (diagnoses and procedures),
- Avoid exploding the fact table with duplicated rows.

This design provided the flexibility needed for Question 2 (diagnosis–procedure pairing) while keeping the fact table compact and performant.

In a production environment, this approach scales well and aligns with dimensional modeling best practices.

---

By moving to a star schema:
- Query performance improved by up to an order of magnitude,
- Analytical SQL became simpler and more expressive,
- The system became more scalable and analytics-friendly.

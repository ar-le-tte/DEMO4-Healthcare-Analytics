# Healthcare Data Warehouse – Star Schema

This project demonstrates the transformation of a normalized **OLTP healthcare database** into a **dimensional data warehouse (star schema)** designed for analytical workloads.

The original OLTP schema is optimized for transactional integrity and operational use, but it requires complex joins and runtime aggregations for analytics:

![OLTP Schema](OLTP%20Schema/OLTP_schema%20ERD.png)

The redesigned star schema centralizes analytical facts and exposes descriptive dimensions to support fast, predictable reporting:

![Star Schema](Star%20Schema/star_schema%20ERD.png)

## Project Structure
```text
DEMO4/
│
├── Star Schema/
│ ├── etl_design.txt
│ ├── star_schema.sql
│ ├── star_schema_queries.txt
│ ├── star_schema ERD.pdf
│ └── star_schema ERD.png  
│
├── OLTP Schema/
│ ├── OLTP_schema.sql
│ ├── OLTP_schema ERD.pdf
│ ├── OLTP_schema ERD.png
│ └── query_analysis.txt
│
├── design_decisions.txt
└── reflection.md
```
## File Overview

### `OLTP Schema.sql`
Defines the original normalized transactional schema, populates it and test run the queries.

### `query_analysis.txt`
Contains OLTP analytical queries, execution plans, and observed performance issues.

### `OLTP_schema ERD`
Entity-relationship diagram of the OLTP schema.

### `design_decisions.txt`
Explains the modeling choices behind the star schema (fact grain, dimensions, bridges).

### `star_schema.sql`
DDL for the dimensional warehouse schema (fact, dimensions, bridges, indexes), population and querying.

### `etl_design.txt`
Describes the ETL strategy, load frequency, and handling of late-arriving data.

### `star_schema_queries.txt`
Optimized analytical queries rewritten for the star schema.

### `star_schema ERD`
Entity-relationship diagram of the star schema.

### `reflection.md`
Summary of performance gains, trade-offs, and lessons learned.


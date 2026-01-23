# Healthcare Data Warehouse – Star Schema

This project transforms a normalized **OLTP healthcare database** into a **star schema** optimized for analytical queries.  
The objective is to improve performance, simplify SQL, and separate transactional and analytical workloads.

---

## Project Structure
```text
DEMO4/
│
├── Star Schema/
│ ├── etl_design.txt
│ ├── star_schema.sql
│ ├── star_schema_queries.txt
│ └── star_schema_ERD.pdf
│
├── Test Runs/
│ ├── OLTP Schema.sql
│ ├── design_decisions.txt
│ └── query_analysis.txt
│
└── reflection.md
```
## File Overview

### `OLTP Schema.sql`
Defines the original normalized transactional schema.

### `query_analysis.txt`
Contains OLTP analytical queries, execution plans, and observed performance issues.

### `design_decisions.txt`
Explains the modeling choices behind the star schema (fact grain, dimensions, bridges).

### `star_schema.sql`
DDL for the dimensional warehouse schema (fact, dimensions, bridges, indexes).

### `etl_design.txt`
Describes the ETL strategy, load frequency, and handling of late-arriving data.

### `star_schema_queries.txt`
Optimized analytical queries rewritten for the star schema.

### `star_schema_ERD.pdf`
Entity-relationship diagram of the star schema.

### `reflection.md`
Summary of performance gains, trade-offs, and lessons learned.


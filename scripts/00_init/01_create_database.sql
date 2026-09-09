/*
=============================================================================
  01_create_database.sql
  ----------------------
  Purpose:  Initialize the NovaCRM Analytics data warehouse database and
            create the three medallion-architecture schemas (bronze, silver, gold).
  
  Why separate schemas?
  - Isolates pipeline stages so analysts query gold while engineers debug bronze.
  - Mirrors how enterprise warehouses organize data — a key talking point
    in Deloitte interviews about data governance and access control.
  
  Prerequisites:
  - SQL Server Express (or Developer Edition) installed locally
  - Run this script in SSMS connected as sysadmin or a user with CREATE DATABASE rights
  
  Usage:
  - Execute this script FIRST, before any other scripts in the project.
=============================================================================
*/

-- ---------------------------------------------------------------------------
-- Step 1: Create the database (idempotent — skips if it already exists)
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NovaCRM_DWH')
BEGIN
    CREATE DATABASE NovaCRM_DWH;
    PRINT '>> Database [NovaCRM_DWH] created successfully.';
END
ELSE
BEGIN
    PRINT '>> Database [NovaCRM_DWH] already exists — skipping creation.';
END
GO

USE NovaCRM_DWH;
GO

-- ---------------------------------------------------------------------------
-- Step 2: Create schemas for each medallion layer
-- ---------------------------------------------------------------------------
-- Bronze: raw landing zone — data as-is from source CSVs, all VARCHAR
-- Rationale: VARCHAR columns prevent load failures from unexpected source data.
--            We defer type enforcement to the silver layer.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO
PRINT '>> Schema [bronze] ready.';
GO

-- Silver: cleaned, typed, standardized — where data quality lives
-- Rationale: This layer is where we enforce NOT NULL, correct types, 
--            standardize country names, parse dates, and deduplicate.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO
PRINT '>> Schema [silver] ready.';
GO

-- Gold: business-ready star schema — fact + dimension tables
-- Rationale: Optimized for analytical queries (joins, aggregations).
--            Surrogate keys decouple the warehouse from source system IDs.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO
PRINT '>> Schema [gold] ready.';
GO

PRINT '>> Database initialization complete. Proceed with bronze DDL.';
GO

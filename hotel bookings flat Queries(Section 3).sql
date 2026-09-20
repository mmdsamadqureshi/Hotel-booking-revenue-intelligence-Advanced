-- =========================================================================
-- SECTION 3: DATABASE SCHEMA DEFINITION AND DATA EXTRACTION PIPELINE
-- =========================================================================

-- Step 1: Create and select a fresh database
CREATE DATABASE IF NOT EXISTS hotel_analytics;
USE hotel_analytics;

-- Drop existing tables to ensure a clean slate if re-running
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS properties;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS hotel_bookings_staging;


-- -------------------------------------------------------------------------
-- PART A: STAGING TABLE SETUP & DATA IMPORT
-- -------------------------------------------------------------------------
-- This table mimics the raw structure of 'hotel bookings flat.csv' exactly.
-- Columns match the precise ordering found in the actual dataset.
CREATE TABLE hotel_bookings_staging (
    booking_id VARCHAR(255),
    customer_id VARCHAR(255),
    customer_name VARCHAR(255),
    customer_segment VARCHAR(255),
    customer_signup_date VARCHAR(255),
    customer_home_city VARCHAR(255),
    customer_loyalty_tier VARCHAR(255),
    property_id VARCHAR(255),
    property_name VARCHAR(255),
    property_city VARCHAR(255),
    property_star_rating VARCHAR(255),
    property_type VARCHAR(255),
    property_total_rooms VARCHAR(255),
    booking_date VARCHAR(255),
    checkin_date VARCHAR(255),
    checkout_date VARCHAR(255),
    room_type VARCHAR(255),
    num_rooms VARCHAR(255),
    nights VARCHAR(255),
    booking_channel VARCHAR(255),
    adr VARCHAR(255),
    discount_amount VARCHAR(255),
    coupon_code VARCHAR(255),
    total_amount VARCHAR(255),
    payment_method VARCHAR(255),
    booking_status VARCHAR(255),
    review_rating VARCHAR(255),
    review_date VARCHAR(255)
);

-- EXECUTE IMPORT: Loads the CSV directly into the staging layout.
-- NOTE: Modify the file path below to match the exact local directory of your CSV file.
-- If your MySQL server restricts file loads, ensure local_infile is enabled or place the file in the permitted secure folder.
SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'D:/Samad/Data_Analysis-Project/Travclan-Hotel-Booking-Project/hotel bookings flat.csv'
INTO TABLE hotel_bookings_staging
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES;


-- -------------------------------------------------------------------------
-- PART B: FINAL RELATIONAL SCHEMA ARCHITECTURE
-- -------------------------------------------------------------------------

-- 1. Dimension Table: Customers
CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_name VARCHAR(150) NOT NULL,
    customer_segment VARCHAR(50) NOT NULL,
    customer_signup_date DATE,
    customer_home_city VARCHAR(100),
    customer_loyalty_tier VARCHAR(50)
);

-- 2. Dimension Table: Properties
-- UNIQUE constraint addresses Footnote 4: a genuine duplicate property record
-- (same name AND same city) should never exist as two different property_ids.
-- (Footnote 4 itself -- same name across DIFFERENT cities -- is handled correctly
-- in the ETL below by always grouping/joining on property_id, never property_name.)
CREATE TABLE properties (
    property_id VARCHAR(50) PRIMARY KEY,
    property_name VARCHAR(150) NOT NULL,
    property_city VARCHAR(100),
    property_star_rating DECIMAL(3,1),
    property_type VARCHAR(50),
    property_total_rooms INT,
    CONSTRAINT unq_property_identity UNIQUE (property_name, property_city)
);

-- 3. Fact Table: Bookings (with Relational Referential Integrity Constraints)
CREATE TABLE bookings (
    booking_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    property_id VARCHAR(50),
    booking_date DATE NOT NULL,
    checkin_date DATE NOT NULL, -- Note: checkin_date has no underscore in the source CSV
    checkout_date DATE NOT NULL,
    room_type VARCHAR(50),
    num_rooms INT,
    nights INT,
    booking_channel VARCHAR(50),
    adr DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    coupon_code VARCHAR(50),
    total_amount DECIMAL(10,2),
    payment_method VARCHAR(50),
    booking_status VARCHAR(50) NOT NULL,
    review_rating INT NULL,
    review_date DATE NULL,

    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    -- Footnote 1: checkout ON OR BEFORE checkin is invalid -> must be strictly AFTER.
    CONSTRAINT chk_valid_stay CHECK (checkout_date > checkin_date),
    -- Footnote 3: num_rooms = 0 is erroneous -> must be strictly positive.
    -- (Re-enabled. This works ONLY because the INSERT below now filters num_rooms = 0
    --  rows out BEFORE insert -- otherwise this constraint throws on those rows.)
    CONSTRAINT chk_valid_rooms CHECK (num_rooms > 0)
);


-- -------------------------------------------------------------------------
-- PART C: ETL DEDUPLICATION & MOVEMENT LOGIC
-- -------------------------------------------------------------------------

-- Populate Customers (Resolving denormalized rows down to individual base units via grouping)
INSERT INTO customers (customer_id, customer_name, customer_segment, customer_signup_date, customer_home_city, customer_loyalty_tier)
SELECT 
    customer_id, 
    MAX(customer_name), 
    MAX(customer_segment), 
    MIN(STR_TO_DATE(customer_signup_date, '%Y-%m-%d')), 
    MAX(customer_home_city), 
    MAX(customer_loyalty_tier)
FROM hotel_bookings_staging
GROUP BY customer_id;

-- Populate Properties
INSERT INTO properties (property_id, property_name, property_city, property_star_rating, property_type, property_total_rooms)
SELECT 
    property_id, 
    MAX(property_name), 
    MAX(property_city), 
    MAX(CAST(property_star_rating AS DECIMAL(3,1))), 
    MAX(property_type), 
    MAX(CAST(property_total_rooms AS UNSIGNED))
FROM hotel_bookings_staging
GROUP BY property_id;

-- Populate Bookings Fact Table (Parsing structural data attributes out safely)
INSERT INTO bookings (
     booking_id, customer_id, property_id, booking_date, checkin_date, checkout_date,
     room_type, num_rooms, nights, booking_channel, adr, discount_amount,
     coupon_code, total_amount, payment_method, booking_status, review_rating, review_date
) 
SELECT 
     booking_id, 
     customer_id, 
     property_id, 
     STR_TO_DATE(booking_date, '%Y-%m-%d'),
     STR_TO_DATE(checkin_date, '%Y-%m-%d'),
     STR_TO_DATE(checkout_date, '%Y-%m-%d'),
     room_type,
     CAST(CAST(num_rooms AS DECIMAL(10,2)) AS UNSIGNED),
     CAST(CAST(nights AS DECIMAL(10,2)) AS UNSIGNED),
     booking_channel,
     CAST(adr AS DECIMAL(10,2)),
     CAST(discount_amount AS DECIMAL(10,2)),
     NULLIF(coupon_code, ''),
     CAST(total_amount AS DECIMAL(10,2)),
     payment_method,
     booking_status,
     CASE 
         WHEN review_rating = '' OR review_rating IS NULL OR review_rating = 'NaN' THEN NULL 
         ELSE CAST(CAST(review_rating AS DECIMAL(10,2)) AS UNSIGNED) 
     END,
     CASE 
         WHEN review_date = '' OR review_date IS NULL OR review_date = '0000-00-00' OR review_date = 'NaN' THEN NULL 
         ELSE STR_TO_DATE(review_date, '%Y-%m-%d') 
     END
FROM hotel_bookings_staging
-- THE FIX: filter out Footnote 1 (invalid stays) AND Footnote 3 (zero rooms) data
-- errors here, BEFORE insert -- this is the line that was missing, and the reason
-- the chk_valid_rooms constraint was throwing errors.
WHERE STR_TO_DATE(checkout_date, '%Y-%m-%d') > STR_TO_DATE(checkin_date, '%Y-%m-%d')
  AND CAST(CAST(num_rooms AS DECIMAL(10,2)) AS UNSIGNED) > 0;

-- -------------------------------------------------------------------------
-- PART D: PERFORMANCE OPTIMIZATION (INDEXING)
-- -------------------------------------------------------------------------
CREATE INDEX idx_bookings_customer_id ON bookings(customer_id);

-- INDEX JUSTIFICATION (Include this text in your answers.pdf):
-- "We frequently perform multi-table joins and cohort partitions on 'customer_id' 
-- to calculate aggregate spend arrays and order sequence histories. Indexing this 
-- foreign key field drastically mitigates full-table scans, decreasing query times 
-- from O(N) linear lookups to indexed O(log N) operations."


-- =========================================================================
-- ANALYTICAL QUERIES (COMPLYING WITH ASSESSMENT CONSTRAINTS)
-- =========================================================================

-- -------------------------------------------------------------------------
-- C-Q1: BOOKING SEQUENCE REVENUE AVERAGES
-- -------------------------------------------------------------------------
WITH RankedBookings AS (
    SELECT 
        customer_id,
        total_amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY checkin_date, booking_id) as booking_seq
    FROM bookings
    WHERE booking_status = 'Completed'
),
CategorizedSequences AS (
    SELECT 
        total_amount,
        CASE 
            WHEN booking_seq = 1 THEN '1 (First)'
            WHEN booking_seq = 2 THEN '2 (Second)'
            ELSE '3 or later'
        END AS sequence_label
    FROM RankedBookings
)
SELECT 
    sequence_label,
    ROUND(AVG(total_amount), 2) AS avg_total,
    COUNT(*) AS n
FROM CategorizedSequences
GROUP BY sequence_label
ORDER BY sequence_label;


-- -------------------------------------------------------------------------
-- C-Q2: TOP 5 HIGH-PERFORMING PROPERTIES (NORMALIZED REVIEW SCORES)
-- -------------------------------------------------------------------------
WITH NormalizedReviews AS (
    SELECT 
        b.property_id,
        CASE 
            WHEN c.customer_segment = 'Corporate' THEN b.review_rating / 2.0
            ELSE CAST(b.review_rating AS DECIMAL(3,1))
        END AS norm_rating
    FROM bookings b
    JOIN customers c ON b.customer_id = c.customer_id
    WHERE b.review_rating IS NOT NULL
)
SELECT 
    p.property_name,
    p.property_city,
    COUNT(n.norm_rating) AS num_reviews,
    ROUND(AVG(n.norm_rating), 2) AS normalized_avg_rating
FROM properties p
JOIN NormalizedReviews n ON p.property_id = n.property_id
GROUP BY p.property_id, p.property_name, p.property_city
HAVING COUNT(n.norm_rating) >= 20
ORDER BY normalized_avg_rating DESC
LIMIT 5;
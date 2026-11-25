-- ICT371 Question 7: Water Meter Readings and Billing (MySQL 8.0)
CREATE DATABASE IF NOT EXISTS ict371_q07_water; USE ict371_q07_water;
CREATE TABLE customers(customer_id INT AUTO_INCREMENT PRIMARY KEY,full_name VARCHAR(120) NOT NULL);
CREATE TABLE readings(reading_id BIGINT AUTO_INCREMENT PRIMARY KEY,customer_id INT NOT NULL,reading_month DATE NOT NULL,previous_reading DECIMAL(12,2) NOT NULL,current_reading DECIMAL(12,2) NOT NULL,UNIQUE KEY uq_customer_month(customer_id,reading_month),FOREIGN KEY(customer_id) REFERENCES customers(customer_id),CHECK(previous_reading>=0 AND current_reading>=0),CHECK(DAY(reading_month)=1));
CREATE TABLE bills(bill_id BIGINT AUTO_INCREMENT PRIMARY KEY,reading_id BIGINT NOT NULL UNIQUE,charge DECIMAL(12,2) NOT NULL,amount_paid DECIMAL(12,2) NOT NULL DEFAULT 0,due_on DATE NOT NULL,FOREIGN KEY(reading_id) REFERENCES readings(reading_id),CHECK(charge>=0 AND amount_paid>=0 AND amount_paid<=charge));
CREATE TABLE receivable_snapshot(snapshot_date DATE PRIMARY KEY,total_due DECIMAL(14,2) NOT NULL);
INSERT INTO customers(full_name) VALUES('Wiza'),('Chola'),('Mwamba');
INSERT INTO readings(customer_id,reading_month,previous_reading,current_reading) VALUES(1,'2026-01-01',0,0),(1,'2026-02-01',0,15),(2,'2026-01-01',20,25),(2,'2026-02-01',25,40),(3,'2026-01-01',100,108),(3,'2026-02-01',108,125);
DELIMITER $$
CREATE FUNCTION fn_water_charge(p_units DECIMAL(12,2)) RETURNS DECIMAL(12,2) DETERMINISTIC NO SQL BEGIN IF p_units IS NULL OR p_units<0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Consumption cannot be NULL or negative'; END IF; RETURN ROUND(LEAST(p_units,10)*5+GREATEST(p_units-10,0)*8,2); END$$
CREATE TRIGGER trg_reading_non_decreasing BEFORE INSERT ON readings FOR EACH ROW BEGIN IF NEW.current_reading<NEW.previous_reading THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Current reading below previous'; END IF; END$$
CREATE TRIGGER trg_reading_non_decreasing_update BEFORE UPDATE ON readings FOR EACH ROW BEGIN IF NEW.current_reading<NEW.previous_reading THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Current reading below previous'; END IF; END$$
CREATE PROCEDURE pr_generate_bill(IN p_reading_id BIGINT,IN p_due_on DATE) BEGIN DECLARE v_prev DECIMAL(12,2); DECLARE v_curr DECIMAL(12,2); SELECT previous_reading,current_reading INTO v_prev,v_curr FROM readings WHERE reading_id=p_reading_id; IF v_prev IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown reading'; END IF; IF EXISTS(SELECT 1 FROM bills WHERE reading_id=p_reading_id) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Reading already billed'; END IF; INSERT INTO bills(reading_id,charge,amount_paid,due_on) VALUES(p_reading_id,fn_water_charge(v_curr-v_prev),0,p_due_on); END$$
CREATE PROCEDURE pr_refresh_receivables() BEGIN INSERT INTO receivable_snapshot(snapshot_date,total_due) SELECT CURRENT_DATE,COALESCE(SUM(charge-amount_paid),0) FROM bills ON DUPLICATE KEY UPDATE total_due=VALUES(total_due); END$$
DELIMITER ;
INSERT INTO bills(reading_id,charge,amount_paid,due_on) VALUES(1,0,0,CURRENT_DATE-INTERVAL 5 DAY),(2,90,30,CURRENT_DATE-INTERVAL 2 DAY),(3,25,25,CURRENT_DATE-INTERVAL 1 DAY),(4,90,0,CURRENT_DATE+INTERVAL 3 DAY),(5,40,10,CURRENT_DATE-INTERVAL 4 DAY),(6,106,0,CURRENT_DATE+INTERVAL 5 DAY);
CREATE VIEW v_overdue_bills AS SELECT c.full_name,b.due_on,b.charge-b.amount_paid outstanding_amount FROM bills b JOIN readings r ON r.reading_id=b.reading_id JOIN customers c ON c.customer_id=r.customer_id WHERE b.due_on<CURRENT_DATE AND b.amount_paid<b.charge;
CREATE INDEX ix_bills_due_paid ON bills(due_on,amount_paid);
EXPLAIN SELECT bill_id,charge-amount_paid outstanding FROM bills WHERE due_on<CURRENT_DATE AND amount_paid<charge;
SET GLOBAL event_scheduler=ON; CREATE EVENT IF NOT EXISTS ev_refresh_receivables ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE+INTERVAL 1 DAY,'00:30:00')) DO CALL pr_refresh_receivables();

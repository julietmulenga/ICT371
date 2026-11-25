-- ICT371 Question 1: Pharmacy Stock and Daily Sales
-- MySQL 8.0; enable the event scheduler on the server for the daily event.
CREATE DATABASE IF NOT EXISTS ict371_q01_pharmacy;
USE ict371_q01_pharmacy;
CREATE TABLE medicines (medicine_id INT AUTO_INCREMENT PRIMARY KEY, medicine_name VARCHAR(120) NOT NULL, unit_price DECIMAL(10,2) NOT NULL CHECK(unit_price>0), stock_qty INT NOT NULL CHECK(stock_qty>=0));
CREATE TABLE sales (sale_id BIGINT AUTO_INCREMENT PRIMARY KEY, medicine_id INT NOT NULL, quantity INT NOT NULL CHECK(quantity>0), unit_price DECIMAL(10,2) NOT NULL CHECK(unit_price>0), sold_on DATETIME NOT NULL, FOREIGN KEY(medicine_id) REFERENCES medicines(medicine_id));
CREATE TABLE stock_audit (audit_id BIGINT AUTO_INCREMENT PRIMARY KEY, medicine_id INT NOT NULL, old_qty INT NOT NULL, new_qty INT NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(medicine_id) REFERENCES medicines(medicine_id));
CREATE TABLE daily_sales (sales_date DATE PRIMARY KEY, total_qty BIGINT NOT NULL DEFAULT 0, total_amount DECIMAL(14,2) NOT NULL DEFAULT 0);
INSERT INTO medicines(medicine_name,unit_price,stock_qty) VALUES ('Paracetamol',2.50,100),('Amoxicillin',8.75,60),('Vitamin C',1.25,150);
DELIMITER $$
CREATE FUNCTION fn_sale_value(p_medicine_id INT,p_quantity INT) RETURNS DECIMAL(14,2) DETERMINISTIC READS SQL DATA
BEGIN DECLARE v_price DECIMAL(10,2); IF p_quantity IS NULL OR p_quantity<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Quantity must be positive'; END IF; SELECT unit_price INTO v_price FROM medicines WHERE medicine_id=p_medicine_id; IF v_price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown medicine'; END IF; RETURN v_price*p_quantity; END$$
CREATE TRIGGER trg_medicine_stock_audit AFTER UPDATE ON medicines FOR EACH ROW
BEGIN IF NOT (OLD.stock_qty <=> NEW.stock_qty) THEN INSERT INTO stock_audit(medicine_id,old_qty,new_qty) VALUES(OLD.medicine_id,OLD.stock_qty,NEW.stock_qty); END IF; END$$
CREATE PROCEDURE pr_record_sale(IN p_medicine_id INT,IN p_quantity INT,IN p_sold_on DATETIME)
BEGIN DECLARE v_price DECIMAL(10,2); DECLARE v_stock INT; DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; IF p_quantity IS NULL OR p_quantity<=0 OR p_sold_on IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid sale input'; END IF; START TRANSACTION; SELECT unit_price,stock_qty INTO v_price,v_stock FROM medicines WHERE medicine_id=p_medicine_id FOR UPDATE; IF v_price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown medicine'; END IF; IF v_stock<p_quantity THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient stock'; END IF; INSERT INTO sales(medicine_id,quantity,unit_price,sold_on) VALUES(p_medicine_id,p_quantity,v_price,p_sold_on); UPDATE medicines SET stock_qty=stock_qty-p_quantity WHERE medicine_id=p_medicine_id; COMMIT; END$$
CREATE PROCEDURE pr_refresh_sales(IN p_day DATE)
BEGIN IF p_day IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Date required'; END IF; INSERT INTO daily_sales(sales_date,total_qty,total_amount) SELECT p_day,COALESCE(SUM(quantity),0),COALESCE(SUM(quantity*unit_price),0) FROM sales WHERE sold_on>=p_day AND sold_on<p_day+INTERVAL 1 DAY ON DUPLICATE KEY UPDATE total_qty=VALUES(total_qty),total_amount=VALUES(total_amount); END$$
DELIMITER ;
INSERT INTO sales(medicine_id,quantity,unit_price,sold_on) VALUES (1,2,2.50,NOW()),(2,1,8.75,NOW()),(3,4,1.25,NOW()),(1,3,2.50,NOW()),(2,2,8.75,NOW()),(3,1,1.25,NOW());
CREATE OR REPLACE VIEW v_low_stock AS SELECT medicine_id,medicine_name,unit_price,stock_qty FROM medicines WHERE stock_qty<10;
CREATE INDEX ix_sales_medicine_date ON sales(medicine_id,sold_on);
EXPLAIN SELECT sale_id,quantity,unit_price,sold_on FROM sales WHERE medicine_id=1 AND sold_on BETWEEN '2026-01-01' AND '2026-12-31';
SET GLOBAL event_scheduler=ON;
CREATE EVENT IF NOT EXISTS ev_refresh_daily_sales ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE+INTERVAL 1 DAY,'00:15:00')) DO CALL pr_refresh_sales(CURRENT_DATE-INTERVAL 1 DAY);

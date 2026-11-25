-- ICT371 Question 2: University Fee Payments (MySQL 8.0)
CREATE DATABASE IF NOT EXISTS ict371_q02_fees; USE ict371_q02_fees;
CREATE TABLE Students(student_id INT AUTO_INCREMENT PRIMARY KEY,student_number VARCHAR(30) NOT NULL UNIQUE,full_name VARCHAR(120) NOT NULL,fee_due DECIMAL(12,2) NOT NULL CHECK(fee_due>=0));
CREATE TABLE Payments(payment_id BIGINT AUTO_INCREMENT PRIMARY KEY,student_id INT NOT NULL,amount DECIMAL(12,2) NOT NULL CHECK(amount>0),paid_on DATETIME NOT NULL,FOREIGN KEY(student_id) REFERENCES Students(student_id));
CREATE TABLE payment_audit(audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,payment_id BIGINT NOT NULL,student_id INT NOT NULL,amount DECIMAL(12,2) NOT NULL,logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,FOREIGN KEY(payment_id) REFERENCES Payments(payment_id),FOREIGN KEY(student_id) REFERENCES Students(student_id));
CREATE TABLE daily_collections(collection_date DATE PRIMARY KEY,payment_count BIGINT NOT NULL,total_amount DECIMAL(14,2) NOT NULL);
INSERT INTO Students(student_number,full_name,fee_due) VALUES ('ST001','Amina Phiri',1200),('ST002','Brian Zulu',950),('ST003','Chipo Banda',1500),('ST004','David Tembo',700);
DELIMITER $$
CREATE FUNCTION fn_fee_balance(p_student_id INT) RETURNS DECIMAL(12,2) DETERMINISTIC READS SQL DATA BEGIN DECLARE v_due DECIMAL(12,2); DECLARE v_paid DECIMAL(12,2); SELECT fee_due INTO v_due FROM Students WHERE student_id=p_student_id; IF v_due IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown student'; END IF; SELECT COALESCE(SUM(amount),0) INTO v_paid FROM Payments WHERE student_id=p_student_id; RETURN v_due-v_paid; END$$
CREATE TRIGGER trg_payment_audit AFTER INSERT ON Payments FOR EACH ROW BEGIN INSERT INTO payment_audit(payment_id,student_id,amount) VALUES(NEW.payment_id,NEW.student_id,NEW.amount); END$$
CREATE PROCEDURE pr_receive_payment(IN p_student_id INT,IN p_amount DECIMAL(12,2),IN p_paid_on DATETIME)
BEGIN DECLARE v_balance DECIMAL(12,2); DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END; IF p_amount IS NULL OR p_amount<=0 OR p_paid_on IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment must be positive and dated'; END IF; START TRANSACTION; SELECT fn_fee_balance(p_student_id) INTO v_balance; IF p_amount>v_balance THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Payment exceeds outstanding balance'; END IF; INSERT INTO Payments(student_id,amount,paid_on) VALUES(p_student_id,p_amount,p_paid_on); COMMIT; END$$
CREATE PROCEDURE pr_refresh_collections(IN p_day DATE) BEGIN INSERT INTO daily_collections(collection_date,payment_count,total_amount) SELECT p_day,COUNT(*),COALESCE(SUM(amount),0) FROM Payments WHERE paid_on>=p_day AND paid_on<p_day+INTERVAL 1 DAY ON DUPLICATE KEY UPDATE payment_count=VALUES(payment_count),total_amount=VALUES(total_amount); END$$
DELIMITER ;
INSERT INTO Payments(student_id,amount,paid_on) VALUES(1,200,NOW()),(1,100,NOW()),(2,300,NOW()),(3,250,NOW()),(3,150,NOW()),(3,50,NOW());
CREATE VIEW v_fee_balances AS SELECT s.student_number,s.full_name,fn_fee_balance(s.student_id) outstanding_balance FROM Students s WHERE fn_fee_balance(s.student_id)>0;
CREATE INDEX ix_payments_student_paid ON Payments(student_id,paid_on);
EXPLAIN SELECT payment_id,amount,paid_on FROM Payments WHERE student_id=1 AND paid_on BETWEEN '2026-01-01' AND '2026-12-31';
SET GLOBAL event_scheduler=ON;
CREATE EVENT IF NOT EXISTS ev_refresh_collections ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE+INTERVAL 1 DAY,'01:00:00')) DO CALL pr_refresh_collections(CURRENT_DATE-INTERVAL 1 DAY);

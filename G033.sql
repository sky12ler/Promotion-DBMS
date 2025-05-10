/*
COURSE CODE: UCCD2303 Database Technology
PROGRAMME: CS
GROUP NUMBER: G033
GROUP LEADER NAME & EMAIL: HII ZI WEI cziwei0112@1utar.my
MEMBER 2 NAME: CHIA YUE SHENG
MEMBER 3 NAME: LEE HIEN LEONG
MEMBER 4 NAME: TEH BEE LING
Submission date and time (DD-MON-YY): 29 APRIL 2025
*/

-- Execution Order Mandatory
/*
1. groupscript.sql - Base schema
2. personal_script_1.sql - Membership system
3. personal_script_2.sql - Voucher system (depends on 1e)
4. personal_script_3.sql - setmeal system
5. personal_script_4.sql - seasonalsystem */




-- Alter session
ALTER SESSION SET "_oracle_script" = true;

-- Clean up
-- Drop Tables (in reverse dependency order)
DROP TABLE CUSTOMER_ACTIVITY CASCADE CONSTRAINTS;
DROP TABLE ORDER_ITEMS CASCADE CONSTRAINTS;
DROP TABLE ORDERS CASCADE CONSTRAINTS;
DROP TABLE REDEMPTIONS CASCADE CONSTRAINTS;
DROP TABLE SET_MEAL_COMPONENTS CASCADE CONSTRAINTS;
DROP TABLE CUSTOMER_PROMOTIONS CASCADE CONSTRAINTS;
DROP TABLE PROMOTIONS CASCADE CONSTRAINTS;
DROP TABLE POINT_TRANSACTIONS CASCADE CONSTRAINTS;
DROP TABLE MEMBERSHIP_HISTORY CASCADE CONSTRAINTS;
DROP TABLE MENU_ITEMS CASCADE CONSTRAINTS;
DROP TABLE CUSTOMERS CASCADE CONSTRAINTS;
DROP TABLE MEMBERSHIP_TIERS CASCADE CONSTRAINTS;

-- Drop Sequences
DROP SEQUENCE activity_seq;
DROP SEQUENCE order_item_seq;
DROP SEQUENCE order_seq;
DROP SEQUENCE redemption_seq;
DROP SEQUENCE menu_item_seq;
DROP SEQUENCE tier_seq;
DROP SEQUENCE customer_seq;
DROP SEQUENCE promo_seq;
DROP SEQUENCE history_seq;

-- Drop Users
DROP USER admin_user;
DROP USER manager_user;
DROP USER voucher_user;
DROP USER member_user;
DROP USER report_user;

-- Drop Roles
DROP ROLE promo_admin_role;
DROP ROLE promo_manager_role;
DROP ROLE voucher_admin_role;
DROP ROLE membership_admin_role;
DROP ROLE promo_report_role;


-- Drop Trigger
DROP TRIGGER trg_birthday_check;
DROP TRIGGER trg_sync_point_balance;
DROP TRIGGER trg_membership_history;
DROP TRIGGER trg_auto_assign_vouchers;
DROP TRIGGER trg_order_totals;
DROP TRIGGER trg_promo_usage;


-- Create roles
CREATE ROLE promo_admin_role;
CREATE ROLE promo_manager_role;
CREATE ROLE voucher_admin_role;
CREATE ROLE membership_admin_role;
CREATE ROLE promo_report_role;

-- Create users
CREATE USER admin_user IDENTIFIED BY "Admin@1234" DEFAULT TABLESPACE users;
CREATE USER manager_user IDENTIFIED BY "Manager@1234" DEFAULT TABLESPACE users;
CREATE USER voucher_user IDENTIFIED BY "Voucher@1234" DEFAULT TABLESPACE users;
CREATE USER member_user IDENTIFIED BY "Member@1234" DEFAULT TABLESPACE users;
CREATE USER report_user IDENTIFIED BY "Report@1234" DEFAULT TABLESPACE users;

-- Grant roles to users
GRANT promo_admin_role TO admin_user;
GRANT promo_manager_role TO manager_user;
GRANT voucher_admin_role TO voucher_user;
GRANT membership_admin_role TO member_user;
GRANT promo_report_role TO report_user;

--Grant CREATE SESSION privilege to all users
GRANT CREATE SESSION TO admin_user, manager_user, voucher_user, member_user, report_user;

-- Create sequences
CREATE SEQUENCE tier_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE customer_seq START WITH 1001 INCREMENT BY 1;
CREATE SEQUENCE menu_item_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE promo_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE history_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE order_seq START WITH 5001 INCREMENT BY 1;
CREATE SEQUENCE order_item_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE redemption_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE activity_seq START WITH 1 INCREMENT BY 1;

-- Create tables with inline constraints
CREATE TABLE MEMBERSHIP_TIERS (
    tier_id NUMBER DEFAULT tier_seq.NEXTVAL PRIMARY KEY,
    tier_name VARCHAR2(20) NOT NULL UNIQUE,
    points_required NUMBER NOT NULL CHECK (points_required >= 0),
    discount_percentage NUMBER(5,2) NOT NULL CHECK (discount_percentage BETWEEN 0 AND 100),
    renewal_fee NUMBER(10,2) DEFAULT 0,
    birthday_bonus_points NUMBER DEFAULT 0,
    points_expiry_months NUMBER DEFAULT 12,
    base_earn_rate NUMBER(5,2) DEFAULT 1.0,
    created_date TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE CUSTOMERS (
    customer_id NUMBER DEFAULT customer_seq.NEXTVAL PRIMARY KEY,
    name VARCHAR2(100) NOT NULL,
    email VARCHAR2(100) NOT NULL UNIQUE,
    phone VARCHAR2(15) NOT NULL UNIQUE,
    tier_id NUMBER NOT NULL CONSTRAINT fk_customer_tier REFERENCES MEMBERSHIP_TIERS(tier_id) ON DELETE CASCADE,
    points_balance NUMBER DEFAULT 0 CHECK (points_balance >= 0),
    last_points_earned_date DATE,
    points_expiry_date DATE,
    membership_expiry_date DATE,
    is_member CHAR(1) DEFAULT 'N' CHECK (is_member IN ('Y','N')),
    membership_status VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (membership_status IN ('ACTIVE','CANCELLED','PENDING')),
    last_visit_date DATE,
    join_date DATE DEFAULT SYSDATE,
    birth_date DATE,
    last_renewal_date DATE,
    renewal_count NUMBER DEFAULT 0
);

CREATE TABLE MENU_ITEMS (
    item_id NUMBER DEFAULT menu_item_seq.NEXTVAL PRIMARY KEY,
    item_type VARCHAR2(20) NOT NULL CHECK (item_type IN ('A_LA_CARTE','SET_MEAL','INGREDIENT','SEASONAL')),
    name VARCHAR2(100) NOT NULL,
    description VARCHAR2(200),
    base_price NUMBER(10,2) NOT NULL CHECK (base_price >= 0),
    is_active CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    valid_from DATE DEFAULT SYSDATE,
    valid_to DATE,
    current_stock NUMBER,
    initial_stock NUMBER,
    CONSTRAINT chk_menu_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE PROMOTIONS (
    promotion_id NUMBER DEFAULT promo_seq.NEXTVAL PRIMARY KEY,
    promotion_type VARCHAR2(20) NOT NULL CHECK (promotion_type IN ('VOUCHER','SEASONAL','SET_MEAL')),
    name VARCHAR2(100) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    discount_value NUMBER(10,2),
    voucher_code VARCHAR2(50) UNIQUE,
    is_auto_assign CHAR(1) DEFAULT 'N' CHECK (is_auto_assign IN ('Y','N')),
    points_required NUMBER,
    min_spend NUMBER(10,2),
    set_meal_id NUMBER CONSTRAINT fk_promo_meal REFERENCES MENU_ITEMS(item_id) ON DELETE CASCADE,
    applicable_tier_id NUMBER CONSTRAINT fk_promo_tier REFERENCES MEMBERSHIP_TIERS(tier_id) ON DELETE CASCADE,
    CONSTRAINT chk_disjoint_promo_attrs CHECK (
        (promotion_type = 'VOUCHER' AND discount_value IS NOT NULL) OR
        (promotion_type = 'SEASONAL' AND points_required IS NOT NULL) OR
        (promotion_type = 'SET_MEAL' AND set_meal_id IS NOT NULL)
    ),
    CONSTRAINT chk_valid_dates CHECK (valid_to >= valid_from)
);

CREATE TABLE ORDERS (
    order_id NUMBER DEFAULT order_seq.NEXTVAL PRIMARY KEY,
    customer_id NUMBER NOT NULL CONSTRAINT fk_order_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    order_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    total_amount NUMBER(10,2) NOT NULL CHECK (total_amount >= 0),
    discount_amount NUMBER(10,2) DEFAULT 0 CHECK (discount_amount >= 0),
    final_amount NUMBER(10,2) NOT NULL CHECK (final_amount >= 0),
    payment_method VARCHAR2(50) CHECK (payment_method IN ('CASH','CARD','ONLINE')),
    status VARCHAR2(20) DEFAULT 'COMPLETED' CHECK (status IN ('COMPLETED','CANCELLED','REFUNDED')),
    CONSTRAINT chk_order_amounts CHECK (final_amount = total_amount - discount_amount)
);

CREATE TABLE POINT_TRANSACTIONS (
    transaction_id NUMBER DEFAULT history_seq.NEXTVAL PRIMARY KEY,
    customer_id NUMBER NOT NULL CONSTRAINT fk_pt_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    order_id NUMBER CONSTRAINT fk_pt_order REFERENCES ORDERS(order_id) ON DELETE CASCADE,
    promotion_id NUMBER CONSTRAINT fk_pt_promotion REFERENCES PROMOTIONS(promotion_id) ON DELETE CASCADE,
    points_amount NUMBER NOT NULL,
    transaction_type VARCHAR2(20) NOT NULL CHECK (transaction_type IN 
        ('PURCHASE','REDEMPTION','BONUS','ADJUSTMENT','EXPIRY')),
    transaction_date TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    description VARCHAR2(200),
    expiry_date DATE,
    CONSTRAINT chk_points_amount CHECK (
        (transaction_type IN ('REDEMPTION','EXPIRY') AND points_amount <= 0) OR
        (transaction_type NOT IN ('REDEMPTION','EXPIRY') AND points_amount >= 0)
    )
);

CREATE TABLE MEMBERSHIP_HISTORY (
    history_id NUMBER DEFAULT history_seq.NEXTVAL PRIMARY KEY,
    customer_id NUMBER NOT NULL CONSTRAINT fk_mh_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    old_tier_id NUMBER CONSTRAINT fk_mh_old_tier REFERENCES MEMBERSHIP_TIERS(tier_id) ON DELETE CASCADE,
    new_tier_id NUMBER NOT NULL CONSTRAINT fk_mh_new_tier REFERENCES MEMBERSHIP_TIERS(tier_id) ON DELETE CASCADE,
    change_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    change_reason VARCHAR2(100) CHECK (change_reason IN ('SIGNUP','RENEWAL','UPGRADE','DOWNGRADE','ADMIN','AUTO')),
    changed_by VARCHAR2(30) DEFAULT USER
);

CREATE TABLE CUSTOMER_PROMOTIONS (
    customer_id NUMBER NOT NULL CONSTRAINT fk_cp_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    promotion_id NUMBER NOT NULL CONSTRAINT fk_cp_promotion REFERENCES PROMOTIONS(promotion_id) ON DELETE CASCADE,
    date_acquired DATE DEFAULT SYSDATE,
    is_used CHAR(1) DEFAULT 'N' CHECK (is_used IN ('Y','N')),
    used_date DATE,
    acquisition_method VARCHAR2(20) CHECK (acquisition_method IN ('AUTO_TIER','POINT_REDEEM','MANUAL','BIRTHDAY')),
    PRIMARY KEY (customer_id, promotion_id),
    CONSTRAINT chk_used_date CHECK (is_used = 'N' OR used_date IS NOT NULL)
);

CREATE TABLE REDEMPTIONS (
    redemption_id NUMBER DEFAULT redemption_seq.NEXTVAL PRIMARY KEY,
    customer_id NUMBER NOT NULL CONSTRAINT fk_redemption_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    promotion_id NUMBER NOT NULL CONSTRAINT fk_redemption_promotion REFERENCES PROMOTIONS(promotion_id) ON DELETE CASCADE,
    order_id NUMBER CONSTRAINT fk_redemption_order REFERENCES ORDERS(order_id) ON DELETE CASCADE,
    points_used NUMBER NOT NULL CHECK (points_used >= 0),
    redemption_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    redemption_status VARCHAR2(20) DEFAULT 'COMPLETED' CHECK (redemption_status IN ('COMPLETED','CANCELLED')),
    item_id NUMBER CONSTRAINT fk_redemption_item REFERENCES MENU_ITEMS(item_id) ON DELETE CASCADE
);



CREATE TABLE SET_MEAL_COMPONENTS (
    set_meal_id NUMBER NOT NULL CONSTRAINT fk_smc_meal REFERENCES MENU_ITEMS(item_id) ON DELETE CASCADE,
    component_id NUMBER NOT NULL CONSTRAINT fk_smc_component REFERENCES MENU_ITEMS(item_id) ON DELETE CASCADE,
    quantity NUMBER DEFAULT 1 NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (set_meal_id, component_id),
    CONSTRAINT no_self_reference CHECK (set_meal_id != component_id)
);

CREATE TABLE ORDER_ITEMS (
    order_item_id NUMBER DEFAULT order_item_seq.NEXTVAL PRIMARY KEY,
    order_id NUMBER NOT NULL CONSTRAINT fk_oi_order REFERENCES ORDERS(order_id) ON DELETE CASCADE,
    item_id NUMBER NOT NULL CONSTRAINT fk_oi_item REFERENCES MENU_ITEMS(item_id) ON DELETE CASCADE,
    quantity NUMBER DEFAULT 1 CHECK (quantity > 0),
    price NUMBER(10,2) NOT NULL CHECK (price >= 0),
    discount_applied NUMBER(10,2) DEFAULT 0 CHECK (discount_applied >= 0)
);

CREATE TABLE CUSTOMER_ACTIVITY (
    activity_id NUMBER DEFAULT activity_seq.NEXTVAL PRIMARY KEY,
    customer_id NUMBER CONSTRAINT fk_ca_customer REFERENCES CUSTOMERS(customer_id) ON DELETE CASCADE,
    activity_type VARCHAR2(30) CHECK (activity_type IN ('LOGIN', 'ORDER','SEASONAL_REDEMPTION','SEASONAL_EXPIRATION', 'VOUCHER_REDEMPTION','VOUCHER_GENERATION', 'TIER_CHANGE', 'RENEWAL', 'EXPIRATION', 'VOUCHER_ASSIGNMENT')),
    activity_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    ip_address VARCHAR2(45),
    details VARCHAR2(4000)
);

CREATE OR REPLACE PROCEDURE LOG_ACTIVITY(
    p_customer_id   IN NUMBER,
    p_activity_type IN VARCHAR2,
    p_details       IN VARCHAR2,
    p_ip_address    IN VARCHAR2 DEFAULT NULL 
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO CUSTOMER_ACTIVITY (
        customer_id,
        activity_type,
        activity_date,
        ip_address,
        details
    ) VALUES (
        p_customer_id,
        p_activity_type,
        SYSTIMESTAMP,
        p_ip_address,  -- Will be NULL if not passed
        p_details
    );
    COMMIT;
END;
/




-- Insert data 

-- MEMBERSHIP_TIERS
INSERT INTO MEMBERSHIP_TIERS (tier_name, points_required, discount_percentage, renewal_fee, birthday_bonus_points, points_expiry_months, base_earn_rate) 
VALUES ('Bronze', 0, 5.00, 10.00, 50, 12, 1.0);
INSERT INTO MEMBERSHIP_TIERS (tier_name, points_required, discount_percentage, renewal_fee, birthday_bonus_points, points_expiry_months, base_earn_rate) 
VALUES ('Silver', 500, 10.00, 15.00, 100, 12, 1.2);
INSERT INTO MEMBERSHIP_TIERS (tier_name, points_required, discount_percentage, renewal_fee, birthday_bonus_points, points_expiry_months, base_earn_rate) 
VALUES ('Gold', 1500, 15.00, 20.00, 150, 12, 1.5);
INSERT INTO MEMBERSHIP_TIERS (tier_name, points_required, discount_percentage, renewal_fee, birthday_bonus_points, points_expiry_months, base_earn_rate) 
VALUES ('Platinum', 3000, 20.00, 25.00, 200, 12, 2.0);
INSERT INTO MEMBERSHIP_TIERS (tier_name, points_required, discount_percentage, renewal_fee, birthday_bonus_points, points_expiry_months, base_earn_rate) 
VALUES ('Diamond', 5000, 25.00, 30.00, 250, 12, 2.5);

-- MENU_ITEMS
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('A_LA_CARTE', 'Cheeseburger', 'Classic beef burger with cheese', 8.90, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('A_LA_CARTE', 'Chicken Nuggets', '6-piece nuggets', 7.00, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('A_LA_CARTE', 'Garden Salad', 'Fresh greens with dressing', 5.50, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('A_LA_CARTE', 'Chocolate Shake', 'Creamy chocolate milkshake', 4.50, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SET_MEAL', 'Family Combo', 'Includes 2 burgers, 2 fries, and 2 drinks', 24.90, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SET_MEAL', 'Value Meal', 'Burger, fries, and drink', 12.50, 'Y', NULL, NULL, NULL, NULL);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('INGREDIENT', 'Fries', 'Crispy golden fries', 3.50, 'Y', NULL, NULL, 5000, 5000);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('INGREDIENT', 'Soft Drink', 'Regular fountain drink', 2.50, 'Y', NULL, NULL, 3000, 3000);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SEASONAL', 'Hello Kitty Happy Meal', 'Toy + Kids Meal (Limited Edition)', 12.99, 'Y', DATE '2025-10-15', DATE '2025-11-30', 1000, 1000);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SEASONAL', 'Pumpkin Spice Latte', 'Seasonal autumn drink', 5.90, 'Y', DATE '2025-09-15', DATE '2025-11-15', 200, 200);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SEASONAL', 'Festival Mooncake Set', 'Premium mooncakes (Mid-Autumn Special)', 18.50, 'Y', DATE '2025-09-01', DATE '2025-09-30', 500, 500);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SEASONAL', 'Summer BBQ Burger', 'Special summer edition burger', 9.99, 'Y', DATE '2025-06-01', DATE '2025-08-31', 800, 800);
INSERT INTO MENU_ITEMS (item_type, name, description, base_price, is_active, valid_from, valid_to, current_stock, initial_stock) 
VALUES ('SEASONAL', 'Winter Hot Chocolate', 'Rich hot chocolate with marshmallows', 4.99, 'Y', DATE '2025-12-01', DATE '2026-02-28', 300, 300);

-- SET_MEAL_COMPONENTS 
INSERT INTO SET_MEAL_COMPONENTS VALUES (5, 1, 2);
INSERT INTO SET_MEAL_COMPONENTS VALUES (5, 7, 2);
INSERT INTO SET_MEAL_COMPONENTS VALUES (5, 8, 2);
INSERT INTO SET_MEAL_COMPONENTS VALUES (6, 1, 1);
INSERT INTO SET_MEAL_COMPONENTS VALUES (6, 7, 1);
INSERT INTO SET_MEAL_COMPONENTS VALUES (6, 8, 1);

-- CUSTOMERS
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance, last_points_earned_date, points_expiry_date, membership_expiry_date, is_member, membership_status, last_visit_date, birth_date, last_renewal_date, renewal_count) 
VALUES ('John Smith', 'johnsmith@example.com', '012-3456789', 1, 300, DATE '2024-12-01', DATE '2025-12-01', DATE '2025-12-01', 'Y', 'ACTIVE', DATE '2025-04-01', DATE '1990-04-07', NULL, 0);
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance, last_points_earned_date, points_expiry_date, membership_expiry_date, is_member, membership_status, last_visit_date, birth_date, last_renewal_date, renewal_count) 
VALUES ('Emily Johnson', 'emilyj@example.com', '013-2233445', 2, 750, DATE '2025-03-21', DATE '2026-03-21', DATE '2026-03-21', 'Y', 'ACTIVE', DATE '2025-03-15', DATE '1988-07-12', NULL, 0);
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance, last_points_earned_date, points_expiry_date, membership_expiry_date, is_member, membership_status, last_visit_date, birth_date, last_renewal_date, renewal_count) 
VALUES ('Michael Lee', 'mikelee@example.com', '014-5566778', 3, 1000, DATE '2025-01-10', DATE '2026-01-10', DATE '2026-01-10', 'Y', 'ACTIVE', DATE '2025-01-11', DATE '1995-11-30', NULL, 0);
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance, last_points_earned_date, points_expiry_date, membership_expiry_date, is_member, membership_status, last_visit_date, birth_date, last_renewal_date, renewal_count) 
VALUES ('Sarah Tan', 'saraht@example.com', '015-9988776', 4, 2000, DATE '2025-02-28', DATE '2026-02-28', DATE '2026-02-28', 'Y', 'ACTIVE', DATE '2025-02-28', DATE '1992-03-18', NULL, 0);
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance, last_points_earned_date, points_expiry_date, membership_expiry_date, is_member, membership_status, last_visit_date, birth_date, last_renewal_date, renewal_count) 
VALUES ('David Wong', 'davidw@example.com', '016-1122334', 5, 3200, DATE '2025-03-05', DATE '2026-03-05', DATE '2026-03-05', 'Y', 'ACTIVE', DATE '2025-03-05', DATE '1985-05-25', NULL, 0);
INSERT INTO CUSTOMERS (name, email, phone, tier_id, points_balance,last_points_earned_date, points_expiry_date, membership_expiry_date,is_member, membership_status, last_visit_date, birth_date,last_renewal_date, renewal_count) 
VALUES ('Test User for G001', 'test.user@example.com',  '012-9999999', 1, 500,DATE '2025-03-01',  DATE '2025-12-31',  DATE '2025-03-01',  'Y', 'ACTIVE',  DATE '2025-04-01', DATE '1990-01-01', NULL, 0);




-- PROMOTIONS 
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('VOUCHER', '10% Off', SYSDATE, SYSDATE+30, 10.00, 'DISC10', 'Y', NULL, NULL, NULL, 1);
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('VOUCHER', '20% Off', SYSDATE, SYSDATE+30, 20.00, 'DISC20', 'N', NULL, NULL, NULL, 3);
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('VOUCHER', '5% Off', SYSDATE, SYSDATE+15, 5.00, 'DISC5', 'Y', NULL, NULL, NULL, 1);
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('SEASONAL', 'Hello Kitty Redemption', DATE '2025-10-15', DATE '2025-11-30', NULL, NULL, 'N', 500, 20, 9, NULL);
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('SEASONAL', 'Pumpkin Spice Latte Redemption', DATE '2025-09-01', DATE '2025-09-30', NULL, NULL, 'Y', 300, 30, 10, 3);
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('SET_MEAL', 'Family Combo Discount', SYSDATE, SYSDATE+60, 15.00, NULL, 'N', NULL, 50, 5, NULL);

-- ORDERS 
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1001, SYSDATE, 50.00, 5.00, 45.00, 'CARD', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1002, SYSDATE, 35.00, 0.00, 35.00, 'CASH', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1003, SYSDATE, 60.00, 10.00, 50.00, 'ONLINE', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1004, SYSDATE, 80.00, 15.00, 65.00, 'CARD', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1005, SYSDATE, 25.00, 0.00, 25.00, 'CASH', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1003, SYSDATE, 32.99, 0.00, 32.99, 'CARD', 'COMPLETED');
INSERT INTO ORDERS (customer_id, order_date, total_amount, discount_amount, final_amount, payment_method, status) 
VALUES (1004, SYSDATE, 55.50, 18.50, 37.00, 'ONLINE', 'COMPLETED');

-- POINT_TRANSACTIONS
-- 1. Points that already expired (for testing expired point scenarios)
INSERT INTO POINT_TRANSACTIONS (customer_id, points_amount, transaction_type, description, expiry_date)
VALUES (1006, 100, 'BONUS', 'Expired test points', DATE '2024-12-31');
-- 2. Points expiring soon (within 1 month)
INSERT INTO POINT_TRANSACTIONS (customer_id, points_amount, transaction_type, description, expiry_date)
VALUES (1006, 200, 'PURCHASE', 'Points expiring soon', SYSDATE + 15);
-- 3. Points expiring in 3 months
INSERT INTO POINT_TRANSACTIONS (customer_id, points_amount, transaction_type, description, expiry_date)
VALUES (1006, 300, 'BONUS', 'Mid-term expiring points', ADD_MONTHS(SYSDATE, 3));
-- 4. Points expiring in 1 year (standard)
INSERT INTO POINT_TRANSACTIONS (customer_id, points_amount, transaction_type, description, expiry_date)
VALUES (1006, 400, 'PURCHASE', 'Standard expiry points', ADD_MONTHS(SYSDATE, 12));
-- 5. Negative points (redemption) - doesn't need expiry
INSERT INTO POINT_TRANSACTIONS (customer_id, points_amount, transaction_type, description)
VALUES (1006, -150, 'REDEMPTION', 'Test redemption points');


-- MEMBERSHIP_HISTORY
INSERT INTO MEMBERSHIP_HISTORY (customer_id, old_tier_id, new_tier_id, change_reason)
VALUES (1001, NULL, 1, 'SIGNUP');

INSERT INTO MEMBERSHIP_HISTORY (customer_id, old_tier_id, new_tier_id, change_reason, changed_by)
VALUES (1002, NULL, 1, 'SIGNUP', 'SYSTEM');

INSERT INTO MEMBERSHIP_HISTORY (customer_id, old_tier_id, new_tier_id, change_reason)
VALUES (1003, 1, 2, 'ADMIN');

INSERT INTO MEMBERSHIP_HISTORY (customer_id, old_tier_id, new_tier_id, change_reason, changed_by)
VALUES (1004, NULL, 1, 'SIGNUP', 'JSMITH');

INSERT INTO MEMBERSHIP_HISTORY (customer_id, old_tier_id, new_tier_id, change_reason)
VALUES (1005, 1, 3, 'ADMIN');


-- CUSTOMER_PROMOTIONS 
INSERT INTO CUSTOMER_PROMOTIONS (customer_id, promotion_id, date_acquired, is_used, used_date, acquisition_method) 
VALUES (1001, 1, SYSDATE, 'N', NULL, 'AUTO_TIER');
INSERT INTO CUSTOMER_PROMOTIONS (customer_id, promotion_id, date_acquired, is_used, used_date, acquisition_method) 
VALUES (1002, 2, SYSDATE, 'Y', SYSDATE, 'POINT_REDEEM');
INSERT INTO CUSTOMER_PROMOTIONS (customer_id, promotion_id, date_acquired, is_used, used_date, acquisition_method) 
VALUES (1003, 3, SYSDATE, 'N', NULL, 'MANUAL');
INSERT INTO CUSTOMER_PROMOTIONS (customer_id, promotion_id, date_acquired, is_used, used_date, acquisition_method) 
VALUES (1004, 6, SYSDATE, 'N', NULL, 'BIRTHDAY');
INSERT INTO CUSTOMER_PROMOTIONS (customer_id, promotion_id, date_acquired, is_used, used_date, acquisition_method) 
VALUES (1005, 4, SYSDATE, 'Y', SYSDATE, 'AUTO_TIER');

-- ORDER_ITEMS 
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5001, 1, 1, 8.90, 0);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5002, 3, 2, 7.00, 0);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5003, 2, 1, 24.90, 5.00);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5004, 5, 1, 7.00, 1.00);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5005, 4, 1, 6.90, 0);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5006, 9, 1, 12.99, 0);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5006, 1, 2, 8.90, 0);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5007, 10, 1, 18.50, 18.50);
INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price, discount_applied) 
VALUES (5007, 2, 1, 24.90, 0);

-- REDEMPTIONS 
INSERT INTO REDEMPTIONS (customer_id, promotion_id, order_id, points_used, redemption_status, item_id) 
VALUES (1001, 1, 5001, 100, 'COMPLETED', NULL);
INSERT INTO REDEMPTIONS (customer_id, promotion_id, order_id, points_used, redemption_status, item_id) 
VALUES (1002, 2, 5002, 300, 'COMPLETED', NULL);
INSERT INTO REDEMPTIONS (customer_id, promotion_id, order_id, points_used, redemption_status, item_id) 
VALUES (1003, 3, 5003, 500, 'COMPLETED', NULL);
INSERT INTO REDEMPTIONS (customer_id, promotion_id, order_id, points_used, redemption_status, item_id) 
VALUES (1004, 6, 5007, 300, 'COMPLETED', 10);
INSERT INTO REDEMPTIONS (customer_id, promotion_id, points_used, redemption_status, item_id) 
VALUES (1005, 4, 200, 'COMPLETED', 9);

-- CUSTOMER_ACTIVITY 
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1001, 'LOGIN', '192.168.1.10', 'Logged in from mobile');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1002, 'ORDER', '192.168.1.11', 'Ordered cheeseburger combo');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1003, 'VOUCHER_REDEMPTION', '192.168.1.12', 'Redeemed voucher DISC20');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1004, 'TIER_CHANGE', '192.168.1.13', 'Upgraded to Platinum');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1005, 'LOGIN', '192.168.1.14', 'Web login');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1003, 'SEASONAL_REDEMPTION', '192.168.1.12', 'Redeemed Hello Kitty');
INSERT INTO CUSTOMER_ACTIVITY (customer_id, activity_type, ip_address, details) 
VALUES (1004, 'SEASONAL_REDEMPTION', '192.168.1.13', 'Redeemed Mooncake set');



-- Create Trigger
CREATE OR REPLACE TRIGGER trg_sync_point_balance
FOR INSERT OR UPDATE OR DELETE ON POINT_TRANSACTIONS
COMPOUND TRIGGER
    -- Type declarations for batch processing
    TYPE customer_rec_type IS RECORD (
        points_change NUMBER,
        needs_expiry_recalc BOOLEAN
    );
    
    TYPE customer_map_type IS TABLE OF customer_rec_type INDEX BY PLS_INTEGER;
    v_customer_data customer_map_type;
    
    -- After each row - collect changes
    AFTER EACH ROW IS
    BEGIN
        -- Initialize record for this customer if not exists
        IF NOT v_customer_data.EXISTS(
            CASE WHEN INSERTING OR UPDATING THEN :NEW.customer_id ELSE :OLD.customer_id END
        ) THEN
            v_customer_data(
                CASE WHEN INSERTING OR UPDATING THEN :NEW.customer_id ELSE :OLD.customer_id END
            ) := customer_rec_type(0, FALSE);
        END IF;
        
        -- Handle points change
        IF INSERTING THEN
            v_customer_data(:NEW.customer_id).points_change := 
                v_customer_data(:NEW.customer_id).points_change + :NEW.points_amount;
            
            -- Mark if we need to recalculate expiry date
            IF :NEW.points_amount > 0 AND 
               :NEW.transaction_type IN ('PURCHASE','BONUS') AND
               (:NEW.expiry_date IS NOT NULL) THEN
                v_customer_data(:NEW.customer_id).needs_expiry_recalc := TRUE;
            END IF;
            
        ELSIF UPDATING THEN
            v_customer_data(:NEW.customer_id).points_change := 
                v_customer_data(:NEW.customer_id).points_change + 
                (:NEW.points_amount - NVL(:OLD.points_amount, 0));
                
            -- Mark if we need to recalculate expiry date
            IF (:NEW.points_amount > 0 AND 
                :NEW.transaction_type IN ('PURCHASE','BONUS') AND
                (:NEW.expiry_date IS NOT NULL)) OR
               (:OLD.points_amount > 0 AND 
                :OLD.transaction_type IN ('PURCHASE','BONUS') AND
                (:OLD.expiry_date IS NOT NULL)) THEN
                v_customer_data(:NEW.customer_id).needs_expiry_recalc := TRUE;
            END IF;
            
        ELSE -- DELETING
            v_customer_data(:OLD.customer_id).points_change := 
                v_customer_data(:OLD.customer_id).points_change - :OLD.points_amount;
                
            -- Mark if we need to recalculate expiry date
            IF :OLD.points_amount > 0 AND 
               :OLD.transaction_type IN ('PURCHASE','BONUS') AND
               (:OLD.expiry_date IS NOT NULL) THEN
                v_customer_data(:OLD.customer_id).needs_expiry_recalc := TRUE;
            END IF;
        END IF;
    END AFTER EACH ROW;
    
    -- After statement - process all collected changes
    AFTER STATEMENT IS
    BEGIN
        -- Process all customers with changes
        FOR cust_id IN v_customer_data.FIRST..v_customer_data.LAST LOOP
            CONTINUE WHEN NOT v_customer_data.EXISTS(cust_id);
            
            -- Update customer balance
            UPDATE CUSTOMERS c 
            SET points_balance = points_balance + v_customer_data(cust_id).points_change
            WHERE customer_id = cust_id;
            
            -- Recalculate expiry date if needed
            IF v_customer_data(cust_id).needs_expiry_recalc THEN
                UPDATE CUSTOMERS c 
                SET points_expiry_date = (
                    SELECT MIN(expiry_date) 
                    FROM POINT_TRANSACTIONS pt
                    WHERE pt.customer_id = cust_id
                    AND pt.expiry_date > SYSDATE
                    AND pt.transaction_type IN ('PURCHASE','BONUS')
                    AND pt.points_amount > 0
                )
                WHERE customer_id = cust_id;
            END IF;
            
            -- Tier upgrade/downgrade logic
            FOR tier_rec IN (
                SELECT tier_id 
                FROM MEMBERSHIP_TIERS
                WHERE points_required <= (
                    SELECT points_balance 
                    FROM CUSTOMERS 
                    WHERE customer_id = cust_id
                )
                ORDER BY points_required DESC
                FETCH FIRST 1 ROW ONLY
            ) LOOP
                UPDATE CUSTOMERS 
                SET tier_id = tier_rec.tier_id
                WHERE customer_id = cust_id
                AND tier_id != tier_rec.tier_id;
            END LOOP;
        END LOOP;
    END AFTER STATEMENT;
END trg_sync_point_balance;
/

-- Auto-log membership tier changes
CREATE OR REPLACE TRIGGER trg_membership_history
AFTER UPDATE OF tier_id ON CUSTOMERS
FOR EACH ROW
BEGIN
    INSERT INTO MEMBERSHIP_HISTORY (
        customer_id, old_tier_id, new_tier_id,
        change_reason, changed_by
    ) VALUES (
        :NEW.customer_id, :OLD.tier_id, :NEW.tier_id,
        CASE 
            WHEN :OLD.tier_id IS NULL THEN 'SIGNUP'
            WHEN :NEW.tier_id > :OLD.tier_id THEN 'UPGRADE'
            WHEN :NEW.tier_id < :OLD.tier_id THEN 'DOWNGRADE'
            ELSE 'ADMIN'
        END,
        USER
    );
END;
/

-- Auto-assign vouchers on tier change
CREATE OR REPLACE TRIGGER trg_auto_assign_vouchers
AFTER UPDATE OF tier_id ON CUSTOMERS
FOR EACH ROW
DECLARE
    CURSOR c_vouchers IS
        SELECT promotion_id FROM PROMOTIONS
        WHERE is_auto_assign = 'Y'
        AND valid_from <= SYSDATE AND valid_to >= SYSDATE
        AND (applicable_tier_id IS NULL OR applicable_tier_id = :NEW.tier_id);
BEGIN
    FOR v_rec IN c_vouchers LOOP
        BEGIN
            INSERT INTO CUSTOMER_PROMOTIONS (
                customer_id, promotion_id, acquisition_method
            ) VALUES (
                :NEW.customer_id, v_rec.promotion_id, 
                CASE 
                    WHEN :OLD.tier_id IS NULL THEN 'AUTO_TIER' 
                    ELSE 'TIER_UPGRADE' 
                END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN 
                NULL; -- Skip if already assigned
        END;
    END LOOP;
END;
/

-- Auto-update order totals
CREATE OR REPLACE TRIGGER trg_order_totals
FOR INSERT OR UPDATE OR DELETE ON ORDER_ITEMS
COMPOUND TRIGGER
    -- Variables to store order IDs
    TYPE order_id_array IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_order_ids order_id_array;
    
    -- After each row - collect affected order IDs
    AFTER EACH ROW IS
    BEGIN
        IF INSERTING OR UPDATING THEN
            v_order_ids(:NEW.order_id) := 1;
        ELSE
            v_order_ids(:OLD.order_id) := 1;
        END IF;
    END AFTER EACH ROW;
    
    -- After statement - process all collected orders
    AFTER STATEMENT IS
    BEGIN
        FOR i IN v_order_ids.FIRST..v_order_ids.LAST LOOP
            IF v_order_ids.EXISTS(i) THEN
                UPDATE ORDERS o
                SET total_amount = NVL((
                        SELECT SUM(price * quantity)
                        FROM ORDER_ITEMS
                        WHERE order_id = i
                    ), 0),
                    discount_amount = NVL((
                        SELECT SUM(discount_applied * quantity)
                        FROM ORDER_ITEMS
                        WHERE order_id = i
                    ), 0),
                    final_amount = NVL((
                        SELECT SUM((price - discount_applied) * quantity)
                        FROM ORDER_ITEMS
                        WHERE order_id = i
                    ), 0)
                WHERE order_id = i;
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END trg_order_totals;
/

-- Track promotion usage
CREATE OR REPLACE TRIGGER trg_promo_usage
AFTER INSERT ON REDEMPTIONS
FOR EACH ROW
BEGIN
    UPDATE CUSTOMER_PROMOTIONS
    SET is_used = 'Y',
        used_date = SYSDATE
    WHERE customer_id = :NEW.customer_id
    AND promotion_id = :NEW.promotion_id;
END;
/

-- Birthday check trigger
CREATE OR REPLACE TRIGGER trg_birthday_check
AFTER LOGON ON DATABASE
DECLARE
    v_today_month NUMBER;
    v_today_day NUMBER;
BEGIN
    -- Get current month/day
    v_today_month := EXTRACT(MONTH FROM SYSDATE);
    v_today_day := EXTRACT(DAY FROM SYSDATE);
    
    -- Process customers with birthdays today
    FOR cust IN (
        SELECT c.customer_id, c.tier_id, mt.birthday_bonus_points
        FROM CUSTOMERS c
        JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
        WHERE EXTRACT(MONTH FROM c.birth_date) = v_today_month
        AND EXTRACT(DAY FROM c.birth_date) = v_today_day
    ) LOOP
        BEGIN
            -- Only proceed if there are bonus points to award
            IF cust.birthday_bonus_points > 0 THEN
                -- Insert into POINT_TRANSACTIONS
                INSERT INTO POINT_TRANSACTIONS (
                    customer_id, 
                    points_amount, 
                    transaction_type, 
                    description, 
                    transaction_date, 
                    expiry_date
                ) VALUES (
                    cust.customer_id, 
                    cust.birthday_bonus_points, 
                    'BONUS',
                    'Birthday reward points', 
                    SYSDATE, 
                    ADD_MONTHS(SYSDATE, 12)
                );
                
                -- Insert into CUSTOMER_ACTIVITY
                INSERT INTO CUSTOMER_ACTIVITY (
                    customer_id, 
                    activity_type, 
                    details, 
                    activity_date
                ) VALUES (
                    cust.customer_id, 
                    'BIRTHDAY', 
                    'Received ' || cust.birthday_bonus_points || ' birthday points',
                    SYSDATE
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                NULL; -- Suppress errors to prevent login issues
        END;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        NULL; -- Prevent login failure due to trigger error
END;
/








-- Grant privileges for promo_admin_role
GRANT ALL ON MEMBERSHIP_TIERS TO promo_admin_role;
GRANT ALL ON CUSTOMERS TO promo_admin_role;
GRANT ALL ON PROMOTIONS TO promo_admin_role;
GRANT ALL ON CUSTOMER_PROMOTIONS TO promo_admin_role;
GRANT ALL ON REDEMPTIONS TO promo_admin_role;

-- Grant privileges for promo_manager_role
GRANT SELECT, INSERT, UPDATE ON CUSTOMERS TO promo_manager_role;
GRANT SELECT ON MEMBERSHIP_TIERS TO promo_manager_role;
GRANT SELECT, INSERT, UPDATE ON PROMOTIONS TO promo_manager_role;
GRANT SELECT ON CUSTOMER_PROMOTIONS TO promo_manager_role;
GRANT SELECT ON REDEMPTIONS TO promo_manager_role;

-- Grant privileges for voucher_admin_role (now focused on promotions and redemptions)
GRANT SELECT, INSERT, UPDATE ON PROMOTIONS TO voucher_admin_role;
GRANT SELECT, INSERT, UPDATE ON CUSTOMER_PROMOTIONS TO voucher_admin_role;
GRANT SELECT, INSERT, UPDATE ON REDEMPTIONS TO voucher_admin_role;
GRANT SELECT ON CUSTOMERS TO voucher_admin_role;

-- Grant privileges for membership_admin_role
GRANT SELECT, INSERT, UPDATE ON CUSTOMERS TO membership_admin_role;
GRANT SELECT, INSERT, UPDATE ON MEMBERSHIP_TIERS TO membership_admin_role;
GRANT SELECT, INSERT, UPDATE ON MEMBERSHIP_HISTORY TO membership_admin_role;
GRANT SELECT, INSERT, UPDATE ON POINT_TRANSACTIONS TO membership_admin_role;

-- Grant privileges for promo_report_role (read-only)
GRANT SELECT ON MEMBERSHIP_TIERS TO promo_report_role;
GRANT SELECT ON CUSTOMERS TO promo_report_role;
GRANT SELECT ON PROMOTIONS TO promo_report_role;
GRANT SELECT ON CUSTOMER_PROMOTIONS TO promo_report_role;
GRANT SELECT ON REDEMPTIONS TO promo_report_role;
GRANT SELECT ON MEMBERSHIP_HISTORY TO promo_report_role;
GRANT SELECT ON POINT_TRANSACTIONS TO promo_report_role;
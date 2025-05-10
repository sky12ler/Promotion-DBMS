/*
GROUP NUMBER : G004
PROGRAMME : CS
STUDENT ID : 22ACB04673
STUDENT NAME : CHIA YUE SHENG
Submission date and time (DD-MON-YY): 29 April 2025
*/

-- Every Error Test Case is checked and place commented.
-- Pre-Setup
SET SERVEROUTPUT ON
SET LINESIZE 300;
SET PAGESIZE 100;

--------------------------------------------------------------------------------
-- QUERY 1: SEASONAL ITEM PERFORMANCE
--------------------------------------------------------------------------------
-- User Transaction:
-- Display a list of all seasonal menu items and thier performance metrics.

-- Purpose: 
-- Track sales and redemptions of seasonal items, to evaluate their popularity, 
-- revenue contribution, and promotion effectiveness.
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('##########################################################');
    DBMS_OUTPUT.PUT_LINE('######### QUERY 1: SEASONAL ITEM PERFORMANCE #############');
    DBMS_OUTPUT.PUT_LINE('##########################################################');
END;
/

SELECT 
    mi.item_id,
    mi.name,
    mi.description AS season,
    COUNT(oi.order_item_id) AS total_sold,
    SUM(CASE WHEN o.discount_amount = 0 THEN oi.price ELSE 0 END) AS revenue,
    COUNT(CASE WHEN r.redemption_id IS NOT NULL THEN 1 END) AS points_redemptions,
    ROUND(COUNT(oi.order_item_id) / GREATEST(1, mi.initial_stock) * 100, 2) AS sell_through_rate,
    ROUND(AVG(oi.quantity), 1) AS avg_order_size,
    ROUND(COUNT(CASE WHEN r.redemption_id IS NOT NULL AND o.total_amount >= p.min_spend THEN 1 END) / 
          GREATEST(1, COUNT(r.redemption_id)) * 100, 2) AS min_spend_met
FROM MENU_ITEMS mi
JOIN ORDER_ITEMS oi ON mi.item_id = oi.item_id
JOIN ORDERS o ON oi.order_id = o.order_id
LEFT JOIN REDEMPTIONS r ON o.order_id = r.order_id
LEFT JOIN PROMOTIONS p ON r.promotion_id = p.promotion_id AND p.set_meal_id = mi.item_id
WHERE mi.item_type = 'SEASONAL'
GROUP BY mi.item_id, mi.name, mi.description, mi.initial_stock;

--------------------------------------------------------------------------------
-- DEMO TEST (NORMAL CASE): SEASONAL ITEM
--------------------------------------------------------------------------------
-- Expected Output:
-- A List of seasonal menu item with their respective sales performance data
-- Each row incliudes :
-- Item ID, Item Name, Season/Event, Total units sold, Total revenue. Total number of 
-- points redemptions, Seel-through rate (%) based on initial stock, average quantity 
-- per order, percentage of redemptions where minimun spend was achieved.
--------------------------------------------------------------------------------
-- Example Output:
-- | ITEM_ID |         NAME          | SEASON                            | TOTAL_SOLD | REVENUE | POINTS_REDEMPTIONS | SELL_THROUGH_RATE | AVG_ORDER_SIZE | MIN_SPEND_MET |
---|---------|-----------------------|-----------------------------------|------------|---------|--------------------|-------------------|----------------|---------------|
-- |   10    |Pumpkin Spice Latte    | Seasonal autumn drink             |      1     |    0    |         1          |         .5        |       1        |       0       |   
-- |    9    |Hello Kitty Happy Meal | Toy + Kids Meal (Limited Edition) |      1     |  12.99  |         0          |         .1        |       1        |       0       |
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- QUERY 2: SEASONAL INVENTORY & REDEMPTION STATUS MONITORING
--------------------------------------------------------------------------------
-- User Transaction:
-- Displays real-time inventory and point redemption eligibility status for all seasonal menu items,
-- providing managers with actionable insights for inventory and promotion management.

-- Purpose: 
-- Help monitor stock availability and check if seasonal items are eligible
-- for loyalty redemptions during their active period.
-- To identify items needing restocking or promotion adjustments, and support decision-making for seasonal menu planning
BEGIN
    DBMS_OUTPUT.PUT_LINE('######################################################################');
    DBMS_OUTPUT.PUT_LINE('##### QUERY 2: SEASONAL INVENTORY & REDEMPTION STATUS MONITORING #####');
    DBMS_OUTPUT.PUT_LINE('######################################################################');
END;
/

SELECT 
    mi.item_id,
    mi.name,
    mi.current_stock,
    CEIL(mi.valid_to - SYSDATE) AS days_left_in_season,
    CASE WHEN p.promotion_id IS NOT NULL THEN 'Y' ELSE 'N' END AS redemption_allowed,
    NVL(p.min_spend, 0) AS min_spend_required,
    NVL(p.points_required, 0) AS points_cost
FROM MENU_ITEMS mi
LEFT JOIN PROMOTIONS p ON mi.item_id = p.set_meal_id AND SYSDATE BETWEEN p.valid_from AND p.valid_to
WHERE mi.item_type = 'SEASONAL'
ORDER BY mi.valid_to;

--------------------------------------------------------------------------------
-- DEMO TEST (NORMAL CASE): SEASONAL ITEM
--------------------------------------------------------------------------------
-- Expected Output:
-- Inventory status with days remaining and redemption rules.
-- Including: Item ID and name, current stock quantity, days remaining in season, redemtion eligibility,
-- minimun spend required, points needs for redemtion.

-- Example Output:
-- | ITEM_ID |        NAME             | CURRENT_STOCK | DAYS_LEFT_IN_SEASON | R | MIN_SPEND_REQUIRED | POINTS_COST |
---|---------|-------------------------|---------------|---------------------|---|--------------------|-------------|
-- | 12      | Summer BBQ Burger       |     800       |       126           | N |         0          |      0      |
-- | 11      | Festival Mooncake Set   |     500       |       156           | N |         0          |      0      |
-- | 10      | Pumpkin Spice Latte     |     200       |       202           | N |         0          |      0      |
-- | 9       | Hello Kitty Happy Meal  |     1000      |       217           | N |         0          |      0      |
-- | 13      | Winter Hot Chocolate    |     300       |       307           | N |         0          |      0      |
---------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FUNCTION 1: Check Redemption Eligibility
--------------------------------------------------------------------------------
-- User Transaction:
-- Check if a customer qualifies to redeem a seasonal menu item using loyalty points,
-- and provides a immediate feedback on eligibility status with specific rejection reasons.

-- Purpose:
-- Verify if a member can redeem a seasonal item with points.

-- Input Arguments:
-- p_customer_id   NUMBER   the ID of the customer to evaluate
-- p_setmeal_id    NUMBER   the ID of the seasonal menu item
-- p_setmeal_price NUMBER   current price of item in the order

-- Return:
-- ELIGIBLE or error message (e.g., INSUFFICIENT_POINTS, MIN_SPEND_NOT_MET).
--------------------------------------------------------------------------------

-----------------------------------------
-- Enhanced FN_CHECK_SEASONAL_REDEMPTION
-----------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('############################################################');
    DBMS_OUTPUT.PUT_LINE('######### FUNCTION 1: CHECK REDEMPTION ELIGIBILITY #########');
    DBMS_OUTPUT.PUT_LINE('############################################################');
END;
/

CREATE OR REPLACE FUNCTION FN_CHECK_SEASONAL_REDEMPTION(
    p_customer_id IN NUMBER,
    p_setmeal_id IN NUMBER,
    p_setmeal_price IN NUMBER
) RETURN VARCHAR2 AS
    v_promo_rec PROMOTIONS%ROWTYPE;
    v_points_balance NUMBER;
    v_has_voucher NUMBER;
BEGIN
    -- Check if seasonal promotion exists
    BEGIN
        SELECT p.*
        INTO v_promo_rec
        FROM PROMOTIONS p
        WHERE p.set_meal_id = p_setmeal_id
        AND p.promotion_type = 'SEASONAL'
        AND p.valid_from <= SYSDATE
        AND p.valid_to >= SYSDATE
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'NO_PROMOTION';
    END;

    -- Check points balance
    BEGIN
        SELECT points_balance
        INTO v_points_balance
        FROM CUSTOMERS
        WHERE customer_id = p_customer_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'INVALID CUSTOMER';
    END;

    IF v_points_balance < NVL(v_promo_rec.points_required, 0) THEN
        RETURN 'INSUFFICIENT_POINTS';
    END IF;

    -- Check min spend
    IF v_promo_rec.min_spend IS NOT NULL AND p_setmeal_price < v_promo_rec.min_spend THEN
        RETURN 'MIN_SPEND_NOT_MET';
    END IF;

    -- Check tier restriction
    IF v_promo_rec.applicable_tier_id IS NOT NULL THEN
        DECLARE
            v_customer_tier NUMBER;
        BEGIN
            SELECT tier_id
            INTO v_customer_tier
            FROM CUSTOMERS
            WHERE customer_id = p_customer_id;
            
            IF v_customer_tier < v_promo_rec.applicable_tier_id THEN
                RETURN 'TIER_RESTRICTED';
            END IF;
        END;
    END IF;

    RETURN 'ELIGIBLE';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'CHECK_ERROR';
END;
/

-- Setup test data
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, voucher_code, is_auto_assign, points_required, min_spend, set_meal_id, applicable_tier_id) 
VALUES ('SEASONAL', 'Mooncake Set Redemtion', SYSDATE, SYSDATE+30, NULL, NULL, 'Y', 400, 15, 11, 2);
UPDATE CUSTOMERS SET points_balance = 300 WHERE customer_id = 1001;
UPDATE CUSTOMERS SET points_balance = 750 WHERE customer_id = 1002;
UPDATE CUSTOMERS SET points_balance = 1000 WHERE customer_id = 1003;
UPDATE CUSTOMERS SET points_balance = 500 WHERE customer_id = 1006;


--------------------------------------------------------------------------------
-- DEMO TEST 1 (ELIGIBLE CASE): FN_CHECK_SEASONAL_REDEMPTION
--------------------------------------------------------------------------------
-- Testing with eligible conditions: sufficient points, minimum spend met, and minimum tier achieved.
-- Expected Output:
-- Status with : ELIGIBLE
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('===== TESTING REDEMPTION ELIGIBILITY (ELIGIBLE CONDITION) =====');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1003, 11, 18.5) || ' to this seasional promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST 2 (INELIGIBLE CASE): FN_CHECK_SEASONAL_REDEMPTION
--------------------------------------------------------------------------------
-- Testing with ineligible conditions: No Seasonal Promotion
-- Expected Output:
-- Status like : NO_PROMOTION, INSUFFICIENT_POINTS, MIN_SPEND_NOT_MET, TIER_RESTRICTED, INVALID_CUSTOMER
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('============ TESTING WITH A NON-EXISTENT PROMOTION ============');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1003, 12, 18.5) || ' to this seasonal promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
    DBMS_OUTPUT.PUT_LINE('-');

    DBMS_OUTPUT.PUT_LINE('============ TESTING WITH INSUFFICIENT CUSTOMER POINT =========');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1001, 11, 18.5) || ' to this seasonal promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
    DBMS_OUTPUT.PUT_LINE('-');

    DBMS_OUTPUT.PUT_LINE('============ TESTING WITH INSUFFICIENT MINIMUN SPEND ==========');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1003, 11, 12) || ' to this seasonal promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
    DBMS_OUTPUT.PUT_LINE('-');

    DBMS_OUTPUT.PUT_LINE('============ TESTING WITH AN INELIGIBLE TIER ==================');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1006, 11, 18.5) || ' to this seasonal promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
    DBMS_OUTPUT.PUT_LINE('-');

    DBMS_OUTPUT.PUT_LINE('============ TESTING WITH AN NON-EXISTENT CUSTOMER ============');
    DBMS_OUTPUT.PUT_LINE('Testing Status: ' || FN_CHECK_SEASONAL_REDEMPTION(1010, 11, 18.5) || ' to this seasonal promotion');
    DBMS_OUTPUT.PUT_LINE('===============================================================');
    DBMS_OUTPUT.PUT_LINE('-');
END;
/

ALTER TRIGGER TRG_SYNC_POINT_BALANCE DISABLE;

DELETE FROM PROMOTIONS
WHERE promotion_type = 'SEASONAL' 
  AND name = 'Mooncake Set Redemtion'
  AND set_meal_id = 11
  AND applicable_tier_id = 2;

ALTER TRIGGER TRG_SYNC_POINT_BALANCE ENABLE;

--------------------------------------------------------------------------------
-- FUNCTION 2: Calculate Seasonal Demand
--------------------------------------------------------------------------------
-- User Transaction:
-- Forecast demand for seasonal items based on historical sales.
-- eg.Forecasts how many seasonal items will sell before expiry.Based on past 30-day sales trends.

-- Purpose:
-- Predict demand for seasonal items based on past trends.
-- Assist with inventory planning for seasonal offerings. 

-- Input Arguments:
-- p_item_id            NUMBER    ID of the seasonal menu item (from MENU_ITEMS table)
-- p_days_remaining     NUMBER    Days remaining until seasonal item expires (valid_to date)

-- Return:
-- NUMBER - Predicted quantity needed to meet demand (including 20% buffer)
--------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('############################################################');
    DBMS_OUTPUT.PUT_LINE('########### FUNCTION 2: CALCULATE SEASONAL DEMAND ##########');
    DBMS_OUTPUT.PUT_LINE('############################################################');
END;
/

CREATE OR REPLACE FUNCTION FN_PREDICT_SEASONAL_DEMAND(
    p_item_id IN NUMBER,
    p_days_remaining IN NUMBER
) RETURN NUMBER AS
    v_avg_daily_sales NUMBER;
BEGIN
    -- Get historical daily sales rate
    SELECT AVG(oi.quantity)
    INTO v_avg_daily_sales
    FROM ORDER_ITEMS oi
    JOIN ORDERS o ON oi.order_id = o.order_id
    WHERE oi.item_id = p_item_id
    AND o.order_date BETWEEN SYSDATE-30 AND SYSDATE;

    IF v_avg_daily_sales IS NULL THEN
        RETURN 0; -- item no found
    END IF;
    
    -- Adjust for remaining season days
    RETURN CEIL(v_avg_daily_sales * p_days_remaining * 1.2); -- +20% buffer
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0; -- New item? Default to 0
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): FN_PREDICT_SEASONAL_DEMAND
--------------------------------------------------------------------------------
-- Testing with existing item
-- Expected Output: Number of predicted demand for item
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('====== TESTING DEMAND PREDICTION (NORMAL CONDITION) ======');
    DBMS_OUTPUT.PUT_LINE('Predicted demand for item: ' || FN_PREDICT_SEASONAL_DEMAND(9,15) || ' units');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/

/*
--------------------------------------------------------------------------------
-- DEMO TEST 2 (ITEM NOT FOUND): FN_PREDICT_SEASONAL_DEMAND
--------------------------------------------------------------------------------
-- Testing with no existing item
-- Expected Output: 0 (Due to no existing item)
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('====== TESTING DEMAND PREDICTION (ITEM NOT FOUND) ========');
    DBMS_OUTPUT.PUT_LINE('Predicted demand for item: ' || FN_PREDICT_SEASONAL_DEMAND(22,15) || ' units');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/ */

--------------------------------------------------------------------------------
-- PROCEDURE 1: REDEEM SEASONAL ITEM WITH POINTS
--------------------------------------------------------------------------------
-- User Transaction:
-- Process the redemption of a seasonal item using customer points.

-- Purpose:
-- Process point redemption for seasonal items.
-- Handle the complete seasonal redemption workflow including point deduction.


-- Input Arguments:
-- p_customer_id  VARCHAR2   ID of the redeeming customer
-- p_setmeal_id   NUMBER     ID of the seasonal menu item to redeem
-- p_order_id     NUMBER     ID of the order containing the item
--------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('############################################################');
    DBMS_OUTPUT.PUT_LINE('####### PROCEDURE 1: REDEEM SEASONAL ITEM WITH POINTS ######');
    DBMS_OUTPUT.PUT_LINE('############################################################');
END;
/

CREATE OR REPLACE PROCEDURE PROC_REDEEM_SEASONAL_ITEM(
    p_customer_id IN NUMBER,
    p_setmeal_id IN NUMBER,
    p_order_id IN NUMBER
) AS
    v_promo_id NUMBER;
    v_points_required NUMBER;
    v_points_balance NUMBER;
    v_order_item_exists NUMBER;
    v_base_price NUMBER;
    v_promo_exists NUMBER := 0;
    v_customer_exists NUMBER := 0;
    v_item_exists NUMBER := 0;
    v_order_exists NUMBER := 0;
BEGIN
   
    -- 1) Validate customer exists (for FK_REDEMPTION_CUSTOMER)
    SELECT COUNT(*) INTO v_customer_exists
    FROM CUSTOMERS
    WHERE customer_id = p_customer_id;

    IF v_customer_exists = 0 THEN
        -- No LOG_ACTIVITY here because customer doesn't exist
        RAISE_APPLICATION_ERROR(-20053, 'Invalid customer ID');
    END IF;

    -- Now it is safe to log because customer exists
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Customer ' || p_customer_id || ' validated for seasonal item redemption',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );


    -- 2) Validate menu item exists (for FK_REDEMPTION_ITEM)
    SELECT COUNT(*) INTO v_item_exists
    FROM MENU_ITEMS
    WHERE item_id = p_setmeal_id
    AND item_type = 'SEASONAL';
    
    IF v_item_exists = 0 THEN
        LOG_ACTIVITY(
            p_customer_id,
            'SEASONAL_REDEMPTION',
            'Failed redemption attempt - Invalid seasonal menu item ID: ' || p_setmeal_id,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20054, 'Invalid seasonal menu item ID');
    END IF;

    -- Log item validation
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Seasonal menu item ' || p_setmeal_id || ' validated for customer ' || p_customer_id,
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    -- 3) Validate order exists (for FK_REDEMPTION_ORDER)
    SELECT COUNT(*) INTO v_order_exists
    FROM ORDERS
    WHERE order_id = p_order_id
    AND customer_id = p_customer_id;
    
    IF v_order_exists = 0 THEN
        LOG_ACTIVITY(
            p_customer_id,
            'SEASONAL_REDEMPTION',
            'Failed redemption attempt - Invalid order ID for customer: ' || p_order_id,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20055, 'Invalid order ID for customer');
    END IF;

    -- Log order validation
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Order ' || p_order_id || ' validated for seasonal item redemption',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    -- 4) Verify the order contains the setmeal
    SELECT COUNT(*) INTO v_order_item_exists
    FROM ORDER_ITEMS
    WHERE order_id = p_order_id
    AND item_id = p_setmeal_id;
    
    IF v_order_item_exists = 0 THEN
        LOG_ACTIVITY(
            p_customer_id,
            'SEASONAL_REDEMPTION',
            'Failed redemption attempt - Order does not contain specified setmeal: ' || p_setmeal_id,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20051, 'Order does not contain the specified setmeal');
    END IF;

    -- Log order item validation
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Setmeal ' || p_setmeal_id || ' confirmed in order ' || p_order_id,
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    -- 5) Check if promotion exists (for FK_REDEMPTION_PROMOTION)
    SELECT COUNT(*) INTO v_promo_exists
    FROM PROMOTIONS
    WHERE set_meal_id = p_setmeal_id
    AND promotion_type = 'SEASONAL'
    AND SYSDATE BETWEEN valid_from AND valid_to;
    
    IF v_promo_exists = 0 THEN
        LOG_ACTIVITY(
            p_customer_id,
            'SEASONAL_REDEMPTION',
            'Failed redemption attempt - No valid seasonal promotion found for setmeal: ' || p_setmeal_id,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20050, 'No valid seasonal promotion found for this setmeal');
    END IF;

    -- Log promotion check
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Valid seasonal promotion found for setmeal ' || p_setmeal_id,
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    -- 6) Find applicable seasonal promotion
    SELECT promotion_id, points_required
    INTO v_promo_id, v_points_required
    FROM PROMOTIONS
    WHERE set_meal_id = p_setmeal_id
    AND promotion_type = 'SEASONAL'
    AND SYSDATE BETWEEN valid_from AND valid_to
    AND ROWNUM = 1;

    -- 7) Check customers available points (for points_used >= 0 constraint)
    SELECT points_balance INTO v_points_balance
    FROM CUSTOMERS
    WHERE customer_id = p_customer_id;
    
    IF v_points_balance < v_points_required THEN
        LOG_ACTIVITY(
            p_customer_id,
            'SEASONAL_REDEMPTION',
            'Failed redemption attempt - Insufficient points (Balance: ' || v_points_balance || ', Required: ' || v_points_required || ')',
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20052, 'Insufficient points balance');
    END IF;

    -- Log points check
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Customer ' || p_customer_id || ' has sufficient points for redemption (Points balance: ' || v_points_balance || ')',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    -- 8) Get base price for the setmeal
    SELECT base_price INTO v_base_price
    FROM MENU_ITEMS
    WHERE item_id = p_setmeal_id;

    -- Temporarily disable problematic triggers
    EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_AUTO_ASSIGN_VOUCHERS DISABLE';
    EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_SYNC_POINT_BALANCE DISABLE';

    -- 9) Record the redemption (meets all constraints)
    INSERT INTO REDEMPTIONS (
        customer_id,
        promotion_id,
        order_id,
        points_used,
        redemption_date,
        redemption_status,
        item_id,
        discount_value
    ) VALUES (
        p_customer_id,
        v_promo_id,
        p_order_id,
        v_points_required,
        SYSTIMESTAMP,
        'COMPLETED',
        p_setmeal_id,
        v_base_price
    );

    -- 10) Deduct points
    INSERT INTO POINT_TRANSACTIONS (
        customer_id,
        order_id,
        promotion_id,
        points_amount,
        transaction_type,
        description,
        transaction_date,
        expiry_date
    ) VALUES (
        p_customer_id,
        p_order_id,
        v_promo_id,
        -v_points_required,
        'REDEMPTION',
        'Seasonal item redemption for setmeal ' || p_setmeal_id,
        SYSDATE,
        ADD_MONTHS(SYSDATE, 12)
    );

    -- 11) Apply discount to the order item
    UPDATE ORDER_ITEMS
    SET discount_applied = v_base_price
    WHERE order_id = p_order_id
    AND item_id = p_setmeal_id;

    -- Re-enable triggers
    EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_AUTO_ASSIGN_VOUCHERS ENABLE';
    EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_SYNC_POINT_BALANCE ENABLE';

    COMMIT;

    -- 12) Log success
    LOG_ACTIVITY(
        p_customer_id,
        'SEASONAL_REDEMPTION',
        'Successfully redeemed seasonal item ' || p_setmeal_id || ' using ' || v_points_required || ' points',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    DBMS_OUTPUT.PUT_LINE('Successfully redeemed seasonal item ' || p_setmeal_id || ' using ' || v_points_required || ' points');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        -- Ensure re-enabling of triggers
        EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_AUTO_ASSIGN_VOUCHERS ENABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_SYNC_POINT_BALANCE ENABLE';

        -- Only log if customer exists
        BEGIN
            SELECT 1 INTO v_customer_exists
            FROM CUSTOMERS
            WHERE customer_id = p_customer_id;
        
            -- If found, safe to log
            LOG_ACTIVITY(
                p_customer_id,
                'SEASONAL_REDEMPTION',
                'Failed redemption attempt - No valid seasonal promotion found for setmeal: ' || p_setmeal_id,
                SYS_CONTEXT('USERENV', 'IP_ADDRESS')
            );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL; -- Do not log if customer not found
        END;

        RAISE_APPLICATION_ERROR(-20050, 'No valid seasonal promotion found for this setmeal');

    WHEN OTHERS THEN
        ROLLBACK;
        EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_AUTO_ASSIGN_VOUCHERS ENABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER TRG_SYNC_POINT_BALANCE ENABLE';

        -- Only log if customer exists
        BEGIN
            SELECT 1 INTO v_customer_exists
            FROM CUSTOMERS
            WHERE customer_id = p_customer_id;
        
            -- If found, safe to log
            LOG_ACTIVITY(
                p_customer_id,
                'SEASONAL_REDEMPTION',
                'Error redeeming seasonal item: ' || SQLERRM,
                SYS_CONTEXT('USERENV', 'IP_ADDRESS')
            );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL; -- Do not log if customer not found
        END;

        DBMS_OUTPUT.PUT_LINE('Error redeeming seasonal item: ' || SQLERRM);
        RAISE;

END;
/

-- Set up test environment
UPDATE CUSTOMERS SET points_balance = 600 WHERE customer_id = 1001;

--------------------------------------------------------------------------------
-- DEMO TEST - EXECUTE PROC_REDEEM_SEASONAL_ITEM
--------------------------------------------------------------------------------
-- Create test order specifically for these tests

BEGIN
    DBMS_OUTPUT.PUT_LINE('Adding a record for testing...');
END;
/

INSERT INTO PROMOTIONS (
    promotion_type, name, valid_from, valid_to, 
    points_required, min_spend, set_meal_id
) VALUES (
    'SEASONAL', 'TEST Hello Kitty Promotion', 
    SYSDATE-1, SYSDATE+30, 500, 20, 9
);

DECLARE
    v_test_order_id NUMBER;
BEGIN
    INSERT INTO ORDERS (customer_id, total_amount, discount_amount, final_amount) 
    VALUES (1001, 25, 0, 25)
    RETURNING order_id INTO v_test_order_id;
    
    -- Add seasonal item to order
    INSERT INTO ORDER_ITEMS (order_id, item_id, quantity, price) 
    VALUES (v_test_order_id, 9, 1, 12.99);
    
    -- 1. Test successful redemption
    DBMS_OUTPUT.PUT_LINE('====== TESTING SUCCESSFUL REDEMPTION ======');
    BEGIN
        PROC_REDEEM_SEASONAL_ITEM(
            p_customer_id => 1001,
            p_setmeal_id => 9,
            p_order_id => v_test_order_id
        );
        DBMS_OUTPUT.PUT_LINE('Success - redemption worked as expected');
        DBMS_OUTPUT.PUT_LINE('-');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
    END;
    
    -- 2. Test invalid customer ID (modified to avoid LOG_ACTIVITY constraint error)
    DBMS_OUTPUT.PUT_LINE('====== TESTING INVALID CUSTOMER ID ======');
    BEGIN
        PROC_REDEEM_SEASONAL_ITEM(
            p_customer_id => 999999,
            p_setmeal_id => 9,
            p_order_id => v_test_order_id
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20053 THEN
                DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('-');
            ELSE
                DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
            END IF;
    END;
    
    -- 3. Test invalid seasonal item
    DBMS_OUTPUT.PUT_LINE('====== TESTING INVALID SEASONAL ITEM ======');
    BEGIN
        PROC_REDEEM_SEASONAL_ITEM(
            p_customer_id => 1001,
            p_setmeal_id => 999,
            p_order_id => v_test_order_id
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20054 THEN
                DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('-');
            ELSE
                DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
            END IF;
    END;
    
    -- 4. Test order ownership (using a different order)
    DBMS_OUTPUT.PUT_LINE('====== TESTING ORDER OWNERSHIP ======');
    DECLARE
        v_other_order NUMBER;
    BEGIN
        -- Create an order that doesn't belong to our customer
        INSERT INTO ORDERS (customer_id, total_amount, discount_amount, final_amount) 
        VALUES (1002, 25, 0, 25)
        RETURNING order_id INTO v_other_order;
        
        BEGIN
            PROC_REDEEM_SEASONAL_ITEM(
                p_customer_id => 1001,
                p_setmeal_id => 9,
                p_order_id => v_other_order
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20055 THEN
                    DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                    DBMS_OUTPUT.PUT_LINE('-');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
                END IF;
        END;
    END;
    
    -- 5. Test missing order item
    DBMS_OUTPUT.PUT_LINE('====== TESTING MISSING ORDER ITEM ======');
    DECLARE
        v_empty_order NUMBER;
    BEGIN
        -- Create an order without the seasonal item
        INSERT INTO ORDERS (customer_id, total_amount, discount_amount, final_amount) 
        VALUES (1001, 25, 0, 25)
        RETURNING order_id INTO v_empty_order;
        
        BEGIN
            PROC_REDEEM_SEASONAL_ITEM(
                p_customer_id => 1001,
                p_setmeal_id => 9,
                p_order_id => v_empty_order
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20051 THEN
                    DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                    DBMS_OUTPUT.PUT_LINE('-');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
                END IF;
        END;
    END;
    
    -- 6. Test no valid promotion (fixed date range issue)
    DBMS_OUTPUT.PUT_LINE('====== TESTING NO VALID PROMOTION ======');
    BEGIN
        -- Make promotion dates invalid but maintain valid_from < valid_to
        UPDATE PROMOTIONS 
        SET valid_from = SYSDATE+1, valid_to = SYSDATE+2 
        WHERE set_meal_id = 9;
        
        BEGIN
            PROC_REDEEM_SEASONAL_ITEM(
                p_customer_id => 1001,
                p_setmeal_id => 9,
                p_order_id => v_test_order_id
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20050 THEN
                    DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                    DBMS_OUTPUT.PUT_LINE('-');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
                END IF;
        END;
        
        -- Restore promotion
        UPDATE PROMOTIONS 
        SET valid_from = SYSDATE-1, valid_to = SYSDATE+30 
        WHERE set_meal_id = 9;
    END;
    
    -- 7. Test insufficient points
    DBMS_OUTPUT.PUT_LINE('====== TESTING INSUFFICIENT POINTS ======');
    BEGIN
        -- Set points to 0
        UPDATE CUSTOMERS SET points_balance = 0 WHERE customer_id = 1001;
        
        BEGIN
            PROC_REDEEM_SEASONAL_ITEM(
                p_customer_id => 1001,
                p_setmeal_id => 9,
                p_order_id => v_test_order_id
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20052 THEN
                    DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                    DBMS_OUTPUT.PUT_LINE('-');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
                END IF;
        END;
        
        -- Restore points
        UPDATE CUSTOMERS SET points_balance = 600 WHERE customer_id = 1001;
    END;
    
    -- 8. Test non-seasonal item
    DBMS_OUTPUT.PUT_LINE('====== TESTING NON-SEASONAL ITEM ======');
    DECLARE
        v_regular_item NUMBER;
    BEGIN
        SELECT item_id INTO v_regular_item 
        FROM MENU_ITEMS 
        WHERE item_type != 'SEASONAL' AND ROWNUM = 1;
        
        BEGIN
            PROC_REDEEM_SEASONAL_ITEM(
                p_customer_id => 1001,
                p_setmeal_id => v_regular_item,
                p_order_id => v_test_order_id
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20054 THEN
                    DBMS_OUTPUT.PUT_LINE('Success - got expected error: ' || SQLERRM);
                    DBMS_OUTPUT.PUT_LINE('-');
                ELSE
                    DBMS_OUTPUT.PUT_LINE('UNEXPECTED ERROR: ' || SQLERRM);
                END IF;
        END;
    END;
END;
/

--VERIFICATION
BEGIN
    DBMS_OUTPUT.PUT_LINE('================ Verifty - Point Transaction ==============');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/
SELECT * 
FROM point_transactions 
WHERE customer_id = 1001
AND transaction_type = 'REDEMPTION'
ORDER BY transaction_date DESC;

-- PROCEDURE 2: AUTO-EXPIRE SEASONAL ITEMS
--------------------------------------------------------------------------------
-- User Transaction:
-- Automatically deactivate seasonal items when their season ends.
-- Deactivates expired seasonal items from the menu.Removes linked promotions.

-- Purpose:
-- Deactivate seasonal items when the season ends.
-- Maintain menu integrity by removing expired seasonal items.
-- Keeps the menu current (no outdated items).

-- Input Arguments:
-- none
--------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('############################################################');
    DBMS_OUTPUT.PUT_LINE('########## PROCEDURE 2: AUTO-EXPIRE SEASONAL ITEMS #########');
    DBMS_OUTPUT.PUT_LINE('############################################################');
END;
/

CREATE OR REPLACE PROCEDURE PROC_EXPIRE_SEASONAL_ITEMS AS
    v_count NUMBER := 0;
BEGIN
    -- Temporarily disable trigger to prevent point balance sync issues
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance DISABLE';
    
    -- Deactivate expired seasonal items
    UPDATE MENU_ITEMS
    SET is_active = 'N'
    WHERE item_type = 'SEASONAL'
    AND valid_to < SYSDATE
    AND is_active = 'Y'
    RETURNING COUNT(*) INTO v_count;

    -- Log the deactivation of expired seasonal items
    LOG_ACTIVITY(
        NULL,  -- NULL as it's a batch operation, no specific customer involved
        'SEASONAL_EXPIRATION',
        'Deactivated ' || v_count || ' expired seasonal items',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );
    
    DBMS_OUTPUT.PUT_LINE('Deactivated ' || v_count || ' expired seasonal items');
    
    -- Remove associated promotions
    DELETE FROM PROMOTIONS
    WHERE set_meal_id IN (
        SELECT item_id FROM MENU_ITEMS 
        WHERE item_type = 'SEASONAL' 
        AND valid_to < SYSDATE
    )
    RETURNING COUNT(*) INTO v_count;

    -- Log the removal of associated promotions
    LOG_ACTIVITY(
        NULL,  -- NULL as it's a batch operation, no specific customer involved
        'SEASONAL_EXPIRATION',
        'Removed ' || v_count || ' associated seasonal promotions',
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );
    
    DBMS_OUTPUT.PUT_LINE('Removed ' || v_count || ' associated promotions');
    
    -- Re-enable trigger
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Ensure trigger is re-enabled even if error occurs
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in PROC_EXPIRE_SEASONAL_ITEMS: ' || SQLERRM);
        -- Log failure
        LOG_ACTIVITY(
            NULL,  -- NULL as it's a batch operation
            'ERROR',
            'Error in PROC_EXPIRE_SEASONAL_ITEMS: ' || SQLERRM,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE;
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST (NORMAL CASE): PROC_EXPIRE_SEASONAL_ITEMS
--------------------------------------------------------------------------------
-- Run the procedure to expire seasonal items and remove associated promotions
-- Expected Output:
-- Deactivated X expired seasonal items
-- Removed X associated promotions
--------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('Adding a record for testing...');
END;
/

INSERT INTO MENU_ITEMS (item_type, name, base_price, valid_to, is_active)
VALUES ('SEASONAL', 'Test Seasonal Item', 25.00, SYSDATE + 30, 'Y');  
-- Valid for 30 days
COMMIT;


-- Insert a new promotion related to the seasonal item
INSERT INTO PROMOTIONS (promotion_type, name, valid_from, valid_to, discount_value, set_meal_id)
VALUES ('SET_MEAL', 'Test Seasonal Promo', SYSDATE, SYSDATE + 30, 5, (SELECT item_id FROM MENU_ITEMS WHERE name = 'Test Seasonal Item' AND item_type = 'SEASONAL'FETCH FIRST 1 ROW ONLY));  
-- 5% discount, valid for 30 days
COMMIT;

-- Verify the seasonal item in MENU_ITEMS
BEGIN
    DBMS_OUTPUT.PUT_LINE('============ Verify Seasonal Item in MENU_ITEMS ==========');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/
SELECT item_type, name, base_price, valid_to, is_active
FROM MENU_ITEMS 
WHERE name = 'Test Seasonal Item' AND item_type = 'SEASONAL';

-- Verify the promotion in PROMOTIONS related to the seasonal item
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Verify the promotion in PROMOTIONS related to the seasonal item ===');
    DBMS_OUTPUT.PUT_LINE('=======================================================================');
END;
/

SELECT promotion_type, name, valid_from, valid_to, discount_value, set_meal_id
FROM PROMOTIONS 
WHERE set_meal_id = (
    SELECT DISTINCT item_id 
    FROM MENU_ITEMS 
    WHERE name = 'Test Seasonal Item' AND item_type = 'SEASONAL'
);

BEGIN
    DBMS_OUTPUT.PUT_LINE('Updating the Item Valid Date for Testing...');
    DBMS_OUTPUT.PUT_LINE('Valid Date - 10 days ago, Expire Date - 1 days ago');
    DBMS_OUTPUT.PUT_LINE('');
END;
/
-- If needed, also reset valid_from before setting valid_to to expire the item
UPDATE MENU_ITEMS
SET valid_from = SYSDATE - 10, -- Set the valid_from date to 10 days ago (for example)
    valid_to = SYSDATE - 1  -- Expire the item by setting valid_to to yesterday
WHERE item_type = 'SEASONAL' 
  AND name = 'Test Seasonal Item';
COMMIT;

BEGIN
    DBMS_OUTPUT.PUT_LINE('===== TESTING AUTO-EXPIRE SEASONAL ITEMS (Normal Case)====');
    PROC_EXPIRE_SEASONAL_ITEMS;
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/

-- Check if the seasonal item has been deactivated
BEGIN
    DBMS_OUTPUT.PUT_LINE('======= Showing Seasonal Item has been DEACTIVATED ======');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/
SELECT item_type, name, base_price, valid_to, is_active
FROM MENU_ITEMS WHERE name = 'Test Seasonal Item' AND item_type = 'SEASONAL';

-- Check if the associated promotion has been removed
BEGIN
    DBMS_OUTPUT.PUT_LINE('===== Showing Associated Promotion has been REMOVED ======');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/
SELECT promotion_type, name, valid_from, valid_to, discount_value, set_meal_id
FROM PROMOTIONS 
WHERE set_meal_id = (
    SELECT DISTINCT item_id 
    FROM MENU_ITEMS 
    WHERE name = 'Test Seasonal Item' AND item_type = 'SEASONAL'
);

-- Verify the procedure is valid
BEGIN
    DBMS_OUTPUT.PUT_LINE('================= Showing procedure is VALID =============');
    DBMS_OUTPUT.PUT_LINE('==========================================================');
END;
/
SELECT object_name, status FROM user_objects 
WHERE object_name = 'PROC_REDEEM_SEASONAL_ITEM';

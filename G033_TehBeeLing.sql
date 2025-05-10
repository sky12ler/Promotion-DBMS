/*
GROUP NUMBER : G003
PROGRAMME : CS
STUDENT ID : 2204237
STUDENT NAME : TEH BEE LING
Submission date and time (DD-MON-YY): 29 April 2025
*/


-- Every Error Test Case is checked and place commented.
-- Pre-Setup
SET SERVEROUTPUT ON
SET LINESIZE 500;
SET PAGESIZE 500;

--------------------------------------------------
-- Create required placeholder functions first
--------------------------------------------------
-- These minimal implementations enable compilation and testing of main procedures
-- Will be replaced with full implementations during development

/*
Purpose of these placeholders:
- Provide minimal implementations to avoid dependency errors
- Will be replaced by actual implementations later in the script
- Enable testing of the overall script structure first
*/

-- Simple placeholder for FN_CALC_VOUCHER_VALUE
CREATE OR REPLACE FUNCTION FN_CALC_VOUCHER_VALUE(
    p_voucher_id IN NUMBER,
    p_total_amount IN NUMBER,
    p_customer_id IN NUMBER
) RETURN NUMBER AS
BEGIN
    RETURN 0; -- Default to no discount
END;
/

-- Simple placeholder for PROC_REDEEM_VOUCHER
CREATE OR REPLACE PROCEDURE PROC_REDEEM_VOUCHER(
    p_customer_id IN NUMBER,
    p_voucher_id IN NUMBER,
    p_order_id IN NUMBER
) AS
BEGIN
    NULL; -- Do nothing for now
END;
/

-- Simple placeholder for FN_CHECK_SEASONAL_REDEMPTION
CREATE OR REPLACE FUNCTION FN_CHECK_SEASONAL_REDEMPTION(
    p_customer_id IN NUMBER,
    p_setmeal_id IN NUMBER,
    p_price IN NUMBER
) RETURN VARCHAR2 AS
BEGIN
    RETURN 'ELIGIBLE'; -- Default to eligible
END;
/

-- Simple placeholder for PROC_REDEEM_SEASONAL_ITEM
CREATE OR REPLACE PROCEDURE PROC_REDEEM_SEASONAL_ITEM(
    p_customer_id IN NUMBER,
    p_setmeal_id IN NUMBER,
    p_order_id IN NUMBER
) AS
BEGIN
    NULL; -- Do nothing for now
END;
/

--------------------------------------------------------------------------------
-- FUNCTION 1: FN_VALIDATE_SETMEAL
--------------------------------------------------------------------------------
-- User Transaction:
-- Validate the composition and status of a set meal before order processing.

-- Purpose:
-- Ensure a set meal has valid active components before allowing orders.

-- Input Arguments:
-- p_setmeal_id       NUMBER   ID of the set meal to validate

-- Return:
-- VARCHAR2  Description of the set meal validation status with possible values:
-- 'VALID'               - Set meal meets all validation criteria
-- 'INVALID_SETMEAL'     - Set meal does not exist or is inactive
-- 'NO_COMPONENTS'       - Set meal has no components defined
-- 'INACTIVE_COMPONENTS' - One or more components are inactive
-- 'VALIDATION_ERROR'    - Unexpected system error occurred
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION FN_VALIDATE_SETMEAL(
    p_setmeal_id IN NUMBER
) RETURN VARCHAR2 AS
    v_component_count NUMBER;
    v_active_component_count NUMBER;
BEGIN
    -- Check set meal exists and is active
    BEGIN
        SELECT 1 
        INTO v_component_count
        FROM MENU_ITEMS
        WHERE item_id = p_setmeal_id
        AND item_type = 'SET_MEAL'
        AND is_active = 'Y';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'INVALID_SETMEAL';
    END;

    -- Count all components
    SELECT COUNT(*)
    INTO v_component_count
    FROM SET_MEAL_COMPONENTS
    WHERE set_meal_id = p_setmeal_id;

    -- Count active components
    SELECT COUNT(*)
    INTO v_active_component_count
    FROM SET_MEAL_COMPONENTS smc
    JOIN MENU_ITEMS mi ON smc.component_id = mi.item_id
    WHERE smc.set_meal_id = p_setmeal_id
    AND mi.is_active = 'Y';

    -- Validation rules
    IF v_component_count = 0 THEN
        RETURN 'NO_COMPONENTS';
    ELSIF v_active_component_count < v_component_count THEN
        RETURN 'INACTIVE_COMPONENTS';
    ELSE
        RETURN 'VALID';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'VALIDATION_ERROR';
END;
/

-------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): FN_VALIDATE_SETMEAL
-------------------------------------------------------------------
-- Testing Family Combo (ID 5) which has all active components
-- Expected Output: 'VALID'
-------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING WITH VALID SET MEAL ===');
    DBMS_OUTPUT.PUT_LINE(FN_VALIDATE_SETMEAL(5));  
    DBMS_OUTPUT.PUT_LINE('Expected Output: VALID');
END;
/


---------------------------------------------------------------------
-- DEMO TEST 2 (Non-existent set meal): FN_VALIDATE_SETMEAL
---------------------------------------------------------------------
-- Testing with non-existent ID 999
-- Expected Output: 'INVALID_SETMEAL'
---------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING WITH NON-EXISTENT SET MEAL ===');
    DBMS_OUTPUT.PUT_LINE(FN_VALIDATE_SETMEAL(999));
    DBMS_OUTPUT.PUT_LINE('Expected Output: INVALID_SETMEAL');
END; 
/

-------------------------------------------------------------------------------
-- DEMO TEST 3 (No Components): FN_VALIDATE_SETMEAL
-------------------------------------------------------------------------------
-- Expected Output: 
-- 'NO_COMPONENTS' because the set meal exists but has no associated components.
-------------------------------------------------------------------------------
UPDATE MENU_ITEMS SET item_type = 'SET_MEAL' WHERE item_id = 7;

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING WITH NO COMPONENT SET MEAL ===');
    DBMS_OUTPUT.PUT_LINE(FN_VALIDATE_SETMEAL(7));  
    DBMS_OUTPUT.PUT_LINE('Expected Output: NO_COMPONENTS');
END;
/

UPDATE MENU_ITEMS SET item_type = 'INGREDIENT' WHERE item_id = 7;

---------------------------------------------------------------------------------------------
-- DEMO TEST 4 (Inactive Component): FN_VALIDATE_SETMEAL
---------------------------------------------------------------------------------------------
-- Expected Output:
-- 'INACTIVE_COMPONENTS' because the set meal exists but has one or more inactive components.
---------------------------------------------------------------------------------------------
UPDATE MENU_ITEMS SET is_active = 'N' WHERE item_id = 1;

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING WITH INACTIVE COMPONENT SET MEAL ===');
    DBMS_OUTPUT.PUT_LINE(FN_VALIDATE_SETMEAL(6));
    DBMS_OUTPUT.PUT_LINE('Expected: INACTIVE_COMPONENTS');
END;
/

-- Restore Cheeseburger component to active status
UPDATE MENU_ITEMS SET is_active = 'Y' WHERE item_id = 1;



-------------------------------------------------------------------------------------
-- FUNCTION 2: FN_CALC_SETMEAL_PRICE
-- (Removed logging functionality)
-------------------------------------------------------------------------------------
-- User Transaction:
-- Calculate the final price of a set meal including standard and tier discounts.

-- Purpose:
-- To determine the customer specific price for set meals,
-- ensures that the final price does not drop below a minimum margin.

-- Input Arguments:
-- p_setmeal_id            NUMBER     ID of the set meal to validate
-- p_customer_id           NUMBER     ID of the ordering customer
-- p_apply_tier_discount   BOOLEAN    Whether to include tier discount

-- Return:
-- NUMBER the final price of the set meal after applying standard and tier discounts
------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION FN_CALC_SETMEAL_PRICE(
    p_setmeal_id IN NUMBER,
    p_customer_id IN NUMBER,
    p_apply_tier_discount BOOLEAN DEFAULT TRUE
) RETURN NUMBER AS
    v_component_cost NUMBER := 0;
    v_standard_discount_pct NUMBER := 15;
    v_tier_discount_pct NUMBER := 0;
    v_final_price NUMBER;
BEGIN
    -- Sum component costs
    SELECT SUM(mi.base_price * smc.quantity)
    INTO v_component_cost
    FROM SET_MEAL_COMPONENTS smc
    JOIN MENU_ITEMS mi ON smc.component_id = mi.item_id
    WHERE smc.set_meal_id = p_setmeal_id;

    -- Get tier discount if requested
    IF p_apply_tier_discount THEN
        BEGIN
            SELECT mt.discount_percentage 
            INTO v_tier_discount_pct
            FROM CUSTOMERS c
            JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
            WHERE c.customer_id = p_customer_id;
        EXCEPTION
            WHEN OTHERS THEN
                v_tier_discount_pct := 0;
        END;
    END IF;

    -- Calculate final price with constraints
    v_final_price := GREATEST(
        v_component_cost * (1 - (LEAST(v_standard_discount_pct + v_tier_discount_pct, 50)/100)),
        v_component_cost * 0.7  -- Minimum 30% margin
    );

    RETURN ROUND(v_final_price, 2);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20030, 'Set meal components not found');
END;
/

---------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): FN_CALC_SETMEAL_PRICE
---------------------------------------------------------------------
-- Tests standard pricing calculation for Bronze member
-- Expected Output:
-- Calculated price with 20% total discount (15% standard + 5% tier)
----------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING Bronze member with tier discount ===');
    DBMS_OUTPUT.PUT_LINE('Calculated Price: ' || FN_CALC_SETMEAL_PRICE(5, 1001));
    DBMS_OUTPUT.PUT_LINE('Expected Output: Price with 20% discount (15% standard + 5% tier)');
END;
/

/*
---------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): FN_CALC_SETMEAL_PRICE
---------------------------------------------------------------------
-- Tests error handling for non-existent set meal
-- Expected Output:
-- Error message "Set meal components not found"
----------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING Invalid set meal ===');
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Price: ' || FN_CALC_SETMEAL_PRICE(999, 1001));
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('Expected Output: ORA-20030: Set meal components not found');
END;
/
*/




----------------------------------------------------------------------------------------
-- PROCEDURE 1: PROC_CREATE_ALA_CARTE_ORDER
-- (Fixed syntax errors)
----------------------------------------------------------------------------------------
-- User Transaction: 
-- Create an order for à la carte menu items.

-- Purpose:
-- Process customer orders for individual menu items with optional voucher discounts.

-- Input Arguments:
-- p_customer_id       NUMBER             Ordering customer ID
-- p_item_ids          VARCHAR2           Comma-separated list of item IDs
-- p_payment_method    VARCHAR2           Payment method used for the order
-- p_voucher_id        NUMBER,optional    Optional voucher ID for discount
----------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE PROC_CREATE_ALA_CARTE_ORDER(
    p_customer_id    IN NUMBER,
    p_item_ids       IN VARCHAR2,
    p_payment_method IN VARCHAR2,
    p_voucher_id     IN NUMBER DEFAULT NULL
) AS
    v_order_id        NUMBER;
    v_total_amount    NUMBER := 0;
    v_discount_amount NUMBER := 0;
    v_item_count      NUMBER := 0;
    v_item_price      NUMBER;
    v_customer_exists NUMBER;
    v_order_type      VARCHAR2(20);
BEGIN
    -- 1) Validate customer
    SELECT COUNT(*) 
      INTO v_customer_exists 
      FROM CUSTOMERS 
     WHERE customer_id = p_customer_id
       AND is_member   = 'Y';

    IF v_customer_exists = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Invalid or non-member customer');
    END IF;

    -- 2) Create order header
    INSERT INTO ORDERS (
        customer_id, 
        payment_method, 
        status,
        total_amount,
        discount_amount,
        final_amount
    ) VALUES (
        p_customer_id, 
        p_payment_method, 
        'COMPLETED',
        0, 0, 0
    )
    RETURNING order_id INTO v_order_id;

    -- 3) Process each item
    FOR item_rec IN (
        SELECT TO_NUMBER(TRIM(REGEXP_SUBSTR(p_item_ids,'[^,]+',1,LEVEL))) AS item_id
          FROM DUAL
        CONNECT BY REGEXP_SUBSTR(p_item_ids,'[^,]+',1,LEVEL) IS NOT NULL
    ) LOOP
        BEGIN
            SELECT base_price 
              INTO v_item_price 
              FROM MENU_ITEMS 
             WHERE item_id    = item_rec.item_id
               AND item_type  = 'A_LA_CARTE'
               AND is_active  = 'Y';

            INSERT INTO ORDER_ITEMS (
                order_id, item_id, quantity, price
            ) VALUES (
                v_order_id, item_rec.item_id, 1, v_item_price
            );

            v_total_amount := v_total_amount + v_item_price;
            v_item_count   := v_item_count + 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('Skipped invalid item ID: ' || item_rec.item_id);
        END;
    END LOOP;

    -- 4) Ensure at least one item
    IF v_item_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20011, 'No valid items were processed');
    END IF;

    -- 5) Determine order type for logging
    IF INSTR(p_item_ids, 'SET_MEAL') > 0 THEN
        v_order_type := 'SET_MEAL';
    ELSE
        v_order_type := 'A_LA_CARTE';
    END IF;

    -- 6) Apply voucher (if any)
    IF p_voucher_id IS NOT NULL THEN
        v_discount_amount := FN_CALC_VOUCHER_VALUE(p_voucher_id, v_total_amount, p_customer_id);
        IF v_discount_amount > 0 THEN
            BEGIN
                PROC_REDEEM_VOUCHER(p_customer_id, p_voucher_id, v_order_id);
            EXCEPTION
                WHEN OTHERS THEN
                    v_discount_amount := 0;
                    DBMS_OUTPUT.PUT_LINE('Voucher redemption failed: ' || SQLERRM);
            END;
        END IF;
    END IF;

    -- 7) Update totals
    UPDATE ORDERS
       SET total_amount    = v_total_amount,
           discount_amount = v_discount_amount,
           final_amount    = GREATEST(v_total_amount - v_discount_amount,0)
     WHERE order_id = v_order_id;

    COMMIT;

    -- 8) Log success
    LOG_ACTIVITY(
        p_customer_id,
        'ORDER',
        'Created order #' || v_order_id
          || ' (' || v_order_type || ')'
          || ' items=' || v_item_count
          || ', total=' || v_total_amount
          || ', discount=' || v_discount_amount,
        SYS_CONTEXT('USERENV','IP_ADDRESS')
    );

    DBMS_OUTPUT.PUT_LINE(
      'Successfully created order #'||v_order_id
      ||' with '||v_item_count||' items'
    );

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        -- 9) Log failure
        LOG_ACTIVITY(
            p_customer_id,
            'ORDER',
            'Error creating order: '||SQLERRM,
            SYS_CONTEXT('USERENV','IP_ADDRESS')
        );
        DBMS_OUTPUT.PUT_LINE('Error creating order: '||SQLERRM);
        RAISE;
END;
/


------------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): PROC_CREATE_ALA_CARTE_ORDER
------------------------------------------------------------------------------------
-- Test for a valid customer and valid à la carte items
-- Expected Output:
-- Successfully created order, with total amount calculated and voucher applied.
------------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING VALID ORDER FOR A LA CARTE ===');
    
    PROC_CREATE_ALA_CARTE_ORDER(
        p_customer_id => 1001, 
        p_item_ids => '1,2,3', 
        p_payment_method => 'CARD',
        p_voucher_id => NULL
    );
    
    DBMS_OUTPUT.PUT_LINE('Expected Output: Order successfully created for customer 1001');
END;
/


/*
----------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): PROC_CREATE_ALA_CARTE_ORDER
----------------------------------------------------------------------
-- Test for an invalid customer
-- Expected Output:
-- Error message "Invalid or non-member customer"
----------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID CUSTOMER ID 9999 ===');
    
    BEGIN
        PROC_CREATE_ALA_CARTE_ORDER(
            p_customer_id => 9999, 
            p_item_ids => '1,2', 
            p_payment_method => 'CASH',
            p_voucher_id => NULL
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    END;
    
    DBMS_OUTPUT.PUT_LINE('Expected Output: ORA-20010: Invalid or non-member customer');
END;
/
*/

---------------------------------------------------------------------------------------------------------------
-- PROCEDURE 2: PROC_CREATE_SETMEAL_ORDER
---------------------------------------------------------------------------------------------------------------
-- User Transaction:
-- Create an order for set meals with validation and optional seasonal redemption.

-- Purpose:
-- Handle set meal orders including validation, pricing, and special redemptions.

-- Input Arguments:
-- p_customer_id                 NUMBER              Ordering customer ID
-- p_setmeal_id                  NUMBER              Set meal ID being ordered
-- p_payment_method              VARCHAR2            Payment method used for the order
-- p_voucher_id                  NUMBER,optional     Optional voucher ID to apply a discount to order
-- p_apply_seasonal_redemption   BOOLEAN,optional    Whether to attempt seosonal redemption for the set meal
---------------------------------------------------------------------------------------------------------------
SET DEFINE OFF;


CREATE OR REPLACE PROCEDURE PROC_CREATE_SETMEAL_ORDER(
    p_customer_id IN NUMBER,
    p_setmeal_id IN NUMBER,
    p_payment_method IN VARCHAR2,
    p_voucher_id IN NUMBER DEFAULT NULL,
    p_apply_seasonal_redemption IN BOOLEAN DEFAULT FALSE
) AS
    v_order_id          NUMBER;
    v_setmeal_price     NUMBER;
    v_discount_amount   NUMBER := 0;
    v_promo_discount    NUMBER := 0;
    v_promo_exists      NUMBER := 0;
    v_customer_tier_id  NUMBER;
    v_is_member         CHAR(1);
    v_base_price        NUMBER;
    v_details           VARCHAR2(4000);
    v_total_amount      NUMBER := 0;
    v_final_amount      NUMBER := 0;
BEGIN

    -- 1) Validate customer exists and is a member
    BEGIN
        SELECT tier_id, is_member 
          INTO v_customer_tier_id, v_is_member
          FROM CUSTOMERS 
         WHERE customer_id = p_customer_id;

        IF v_is_member != 'Y' THEN
            RAISE_APPLICATION_ERROR(-20010, 'Customer is not a member');
        END IF;

        LOG_ACTIVITY(
            p_customer_id,
            'ORDER',
            'Customer ' || p_customer_id || ' validated for set meal order',
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20011, 'Customer not found');
    END;

    -- 2) Check if promotion exists for set meal, if not create one
    BEGIN
        SELECT COUNT(*) INTO v_promo_exists
        FROM PROMOTIONS
        WHERE promotion_type = 'SET_MEAL'
          AND set_meal_id = p_setmeal_id
          AND SYSDATE BETWEEN valid_from AND valid_to;

        IF v_promo_exists = 0 THEN
            -- If no promotion exists, create one automatically
            INSERT INTO PROMOTIONS (
                promotion_type, name, valid_from, valid_to, discount_value, set_meal_id
            ) VALUES (
                'SET_MEAL',
                'Auto Promo for Set Meal ' || p_setmeal_id,
                SYSDATE,
                SYSDATE + 30,
                5,  -- default discount value
                p_setmeal_id
            );
            COMMIT;  -- Commit to save promotion immediately

            LOG_ACTIVITY(
                p_customer_id,
                'VOUCHER_ASSIGNMENT',
                'Auto-created promotion for set meal ' || p_setmeal_id,
                SYS_CONTEXT('USERENV', 'IP_ADDRESS')
            );

            DBMS_OUTPUT.PUT_LINE('Auto-created promotion for set meal ID ' || p_setmeal_id);
        END IF;
    END;

    -- 3) Validate set meal exists and is active
    BEGIN
        SELECT base_price
          INTO v_base_price
          FROM MENU_ITEMS
         WHERE item_id = p_setmeal_id
           AND item_type = 'SET_MEAL'
           AND is_active = 'Y';

        LOG_ACTIVITY(
            p_customer_id,
            'ORDER',
            'Set meal ' || p_setmeal_id || ' validated for customer ' || p_customer_id,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20020, 'Set meal not available');
    END;

    -- 4) Calculate the total amount, discount, and final amount
    v_total_amount := v_base_price;  -- Assuming total amount is the base price
    v_discount_amount := 0;  -- Default discount is 0

    -- Apply promo discount if found
    IF v_promo_discount IS NOT NULL THEN
        v_discount_amount := v_promo_discount;
    END IF;

    -- Apply voucher discount if provided
    IF p_voucher_id IS NOT NULL THEN
        v_discount_amount := v_discount_amount + FN_CALC_VOUCHER_VALUE(
                                p_voucher_id, v_total_amount, p_customer_id
                             );
    END IF;

    -- Ensure the discount does not exceed the total amount
    IF v_discount_amount > v_total_amount THEN
        v_discount_amount := v_total_amount;  -- Adjust the discount if it exceeds the total amount
    END IF;

    -- Calculate final amount after applying discount
    v_final_amount := GREATEST(v_total_amount - v_discount_amount, 0);  -- Ensure final amount is not negative

    -- 5) Create order with the calculated amounts
    INSERT INTO ORDERS(
        customer_id, payment_method, status,
        total_amount, discount_amount, final_amount
    ) VALUES (
        p_customer_id, p_payment_method, 'COMPLETED',
        v_total_amount, v_discount_amount, v_final_amount
    ) RETURNING order_id INTO v_order_id;

    -- Add the setmeal item to the order
    INSERT INTO ORDER_ITEMS(
        order_id, item_id, quantity, price
    ) VALUES (
        v_order_id, p_setmeal_id, 1, v_base_price
    );

    -- 6) Log successful order creation
    v_details := 'Created SET_MEAL order #' || v_order_id ||
                 ' with item ' || p_setmeal_id ||
                 ' base price=' || v_base_price ||
                 ' promo discount=' || v_promo_discount ||
                 ' final price=' || v_final_amount;

    LOG_ACTIVITY(
        p_customer_id,
        'ORDER',
        v_details,
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')
    );

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Successfully created set meal order #' || v_order_id);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        v_details := 'Failed to create set meal order: ' || SQLERRM;

        LOG_ACTIVITY(
            p_customer_id,
            'ORDER',
            v_details,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );

        DBMS_OUTPUT.PUT_LINE('Error creating set meal order: ' || SQLERRM);
        RAISE;
END;
/

------------------------------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): PROC_CREATE_SETMEAL_ORDER
------------------------------------------------------------------------------------------------------
-- Test for valid customer, valid set meal, and payment method 'CARD'
-- Expected Output: 
-- Successfully created order with voucher applied, final price calculated.
------------------------------------------------------------------------------------------------------

BEGIN
    -- Testing valid set meal order creation
    DBMS_OUTPUT.PUT_LINE('=== TESTING VALID ORDER FOR SET MEAL ===');
    
    -- Call the procedure to create set meal order
    PROC_CREATE_SETMEAL_ORDER(
        p_customer_id => 1001,  -- Specify customer ID
        p_setmeal_id => 5,      -- Specify set meal ID
        p_payment_method => 'CARD',  -- Payment method (e.g., 'CARD')
        p_voucher_id => 1,      -- Voucher ID (if applicable)
        p_apply_seasonal_redemption => FALSE -- Seasonal redemption flag
    );
    
    DBMS_OUTPUT.PUT_LINE('Expected Output: Successfully created set meal order with voucher applied');
END;
/


/*
------------------------------------------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): PROC_CREATE_SETMEAL_ORDER
------------------------------------------------------------------------------------------------------
-- Test for an invalid set meal, which does not exist or is inactive
-- Expected Output: 
-- Error message "Set meal not available"
------------------------------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID SET MEAL ID 999 ===');
   
    BEGIN
        PROC_CREATE_SETMEAL_ORDER(
            p_customer_id => 1001, 
            p_setmeal_id => 999, 
            p_payment_method => 'CASH', 
            p_voucher_id => NULL, 
            p_apply_seasonal_redemption => FALSE
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    END;
    
    DBMS_OUTPUT.PUT_LINE('Expected Output: ORA-20020: Set meal not available');
END;
/
*/

-----------------------------------------------------------------------------------------------------------------
-- 6. QUERY: Set Meal Profitability Analysis
-----------------------------------------------------------------------------------------------------------------
-- User transaction:
-- List out all set meals with their component costs, profit margins, and recent sales volume,
-- including validation status, ordered by profitability.

-- Purpose: 
-- Analyze the profitability of set meals by comparing component costs to selling prices.
-- Compare cost vs. revenue for each set meal that shows gross profit and sales volume last 3 months.

-- This query retrieves a detailed profitability analysis for set meals, including the total component 
-- cost, gross profit, and margin percentages. It also includes the number of sales made for each set 
-- meal over the last 3 months. The results are ordered by the base margin percentage in descending order.
------------------------------------------------------------------------------------------------------------------

SELECT 
    sm.item_id,
    sm.name,
    sm.base_price AS selling_price,
    SUM(mi.base_price * smc.quantity) AS component_cost,
    sm.base_price - SUM(mi.base_price * smc.quantity) AS gross_profit,
    ROUND((sm.base_price - SUM(mi.base_price * smc.quantity)) / sm.base_price * 100, 2) AS base_margin_pct,
    ROUND((sm.base_price*0.85 - SUM(mi.base_price * smc.quantity)) / (sm.base_price*0.85) * 100, 2) AS discounted_margin_pct,
    FN_VALIDATE_SETMEAL(sm.item_id) AS validation_status,
    (SELECT COUNT(*) FROM ORDER_ITEMS oi JOIN ORDERS o ON oi.order_id = o.order_id 
     WHERE oi.item_id = sm.item_id AND o.order_date > ADD_MONTHS(SYSDATE, -3)) AS sales_last_3_months
FROM MENU_ITEMS sm
JOIN SET_MEAL_COMPONENTS smc ON sm.item_id = smc.set_meal_id
JOIN MENU_ITEMS mi ON smc.component_id = mi.item_id
WHERE sm.item_type = 'SET_MEAL'
GROUP BY sm.item_id, sm.name, sm.base_price
ORDER BY base_margin_pct DESC;

----------------------------------------------------------------------------------------------
-- 7. QUERY: Order Type Comparison
----------------------------------------------------------------------------------------------
-- User transaction:
-- Compare performance metrics between set meals and à la carte orders across customer tiers,
-- including order counts, revenue, and customer engagement metrics.

-- Purpose: 
-- To analyze differences in purchasing method between set meals and à la carte items
-- by customer membership tier, helping identify which order types drive more value
-- from different customer segments.
----------------------------------------------------------------------------------------------

SELECT 
    CASE WHEN mi.item_type = 'SET_MEAL' THEN 'Setmeal' ELSE 'À La Carte' END AS order_type,
    mt.tier_name AS customer_tier,
    COUNT(DISTINCT oi.order_id) AS order_count,
    SUM(oi.price * oi.quantity) AS total_revenue,
    ROUND(AVG(oi.price * oi.quantity), 2) AS avg_order_value,
    ROUND(SUM(oi.price * oi.quantity) / NULLIF(COUNT(DISTINCT o.customer_id), 0), 2) AS revenue_per_customer,
    ROUND(COUNT(DISTINCT oi.order_id) / NULLIF(COUNT(DISTINCT o.customer_id), 0), 2) AS orders_per_customer
FROM ORDER_ITEMS oi
JOIN MENU_ITEMS mi ON oi.item_id = mi.item_id
JOIN ORDERS o ON oi.order_id = o.order_id
JOIN CUSTOMERS c ON o.customer_id = c.customer_id
JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
GROUP BY 
    CASE WHEN mi.item_type = 'SET_MEAL' THEN 'Setmeal' ELSE 'À La Carte' END,
    mt.tier_name
ORDER BY 
    order_type, 
    CASE mt.tier_name 
        WHEN 'Diamond' THEN 1 
        WHEN 'Platinum' THEN 2 
        WHEN 'Gold' THEN 3 
        WHEN 'Silver' THEN 4 
        WHEN 'Bronze' THEN 5 
    END;

---------------------------------------------------------
-- Test à la carte order
---------------------------------------------------------
-- Purpose: Validate the query works with real order data
---------------------------------------------------------
BEGIN
    PROC_CREATE_ALA_CARTE_ORDER(1001, '1,3', 'CARD');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

------------------------------------------------------
-- Test set meal order
------------------------------------------------------
BEGIN
    PROC_CREATE_SETMEAL_ORDER(1002, 5, 'ONLINE');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

------------------------------------------------------------------
-- Verify results
------------------------------------------------------------------
-- Purpose: Validate order calculations match expected amounts
------------------------------------------------------------------

SELECT o.order_id, o.total_amount, o.discount_amount, o.final_amount,
       (SELECT SUM(price * quantity) FROM ORDER_ITEMS WHERE order_id = o.order_id) AS calc_total,
       (SELECT SUM(discount_applied * quantity) FROM ORDER_ITEMS WHERE order_id = o.order_id) AS calc_discount
FROM ORDERS o
WHERE o.order_id IN (
    SELECT MAX(order_id) FROM ORDERS WHERE customer_id = 1001
    UNION
    SELECT MAX(order_id) FROM ORDERS WHERE customer_id = 1002
);
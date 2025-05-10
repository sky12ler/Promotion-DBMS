/*
GROUP NUMBER : G001
PROGRAMME    : CS
STUDENT ID   : 22ACB04587
STUDENT NAME : Hii Zi Wei
Submission date and time (DD-MON-YY): 29 April 2025
*/

-- Every Error Test Case is checked and place commented.
-- Disabling the trigger is using in the bullk assignments of renewal and point expiration. The procedure are designed as automatic operations.
-- Hence, trigger is disable in this case as a bulk insert/update/delete affecting thousands of rows means thousands of trigger executions. A trigger might insert/update other rows that re-fire the same or another trigger.


SET SERVEROUTPUT ON;
SET LINESIZE 200;
SET PAGESIZE 100;

--------------------------------------------------------------------------------
-- PROCEDURE 1: PROC_RENEW_MEMBERSHIPS
--------------------------------------------------------------------------------
-- User Transaction:
-- Renew the memberships of customers whose expiry dates have passed, 
-- are about to expire, or are due in the coming month, depending on the specified type.
-- This allows a staff member or automated system to process bulk renewals,
-- updating status, expiry date, and renewal count.

-- Purpose:
-- To update membership records in batch by extending expiry dates, 
-- resetting status to ACTIVE, and logging success or failure.

-- Input Arguments:
-- p_renewal_type       VARCHAR2   scope of renewals: 'EXPIRED_ONLY', 'URGENT', or 'ALL_DUE'
-- p_extension_months   NUMBER     number of months to extend the expiry by
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PROC_RENEW_MEMBERSHIPS (
    p_renewal_type IN VARCHAR2 DEFAULT 'EXPIRED_ONLY',
    p_extension_months IN NUMBER DEFAULT 12
) AS
    v_renewed_count NUMBER := 0;
    v_failed_count NUMBER := 0;
    v_start_time TIMESTAMP := SYSTIMESTAMP;
    v_triggers_disabled BOOLEAN := FALSE;
BEGIN
    -- Validate parameters
    IF p_renewal_type NOT IN ('EXPIRED_ONLY', 'URGENT', 'ALL_DUE') THEN
        -- Log invalid renewal type
        LOG_ACTIVITY(
            NULL,  -- NULL for batch operation
            'RENEWAL',
            'Invalid renewal type: ' || p_renewal_type,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20001, 'Invalid renewal type. Must be EXPIRED_ONLY, URGENT, or ALL_DUE');
    END IF;

    IF p_extension_months <= 0 THEN
        -- Log invalid extension months
        LOG_ACTIVITY(
            NULL,  -- NULL for batch operation
            'RENEWAL',
            'Invalid extension months: ' || p_extension_months,
            SYS_CONTEXT('USERENV', 'IP_ADDRESS')
        );
        RAISE_APPLICATION_ERROR(-20002, 'Extension months must be positive');
    END IF;

    BEGIN
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance DISABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history DISABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers DISABLE';
        v_triggers_disabled := TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Warning: Could not disable triggers - ' || SUBSTR(SQLERRM, 1, 200));
    END;

    SAVEPOINT before_renewal_batch;

    FOR cust IN (
        SELECT c.customer_id, c.name, mt.renewal_fee, c.membership_expiry_date
        FROM CUSTOMERS c
        JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
        WHERE c.is_member = 'Y'
          AND (
              (p_renewal_type = 'EXPIRED_ONLY' AND c.membership_expiry_date <= SYSDATE) OR
              (p_renewal_type = 'URGENT' AND c.membership_expiry_date BETWEEN SYSDATE AND SYSDATE + 7) OR
              (p_renewal_type = 'ALL_DUE' AND c.membership_expiry_date <= SYSDATE + 30)
          )
        FOR UPDATE
    ) LOOP
        BEGIN
            SAVEPOINT before_customer_renewal;

            DECLARE
                v_payment_received BOOLEAN := TRUE;
                v_new_expiry_date DATE := ADD_MONTHS(GREATEST(cust.membership_expiry_date, SYSDATE), p_extension_months);
            BEGIN
                IF v_payment_received THEN
                    UPDATE CUSTOMERS
                    SET membership_expiry_date = v_new_expiry_date,
                        membership_status = 'ACTIVE',
                        last_renewal_date = SYSDATE,
                        renewal_count = renewal_count + 1
                    WHERE customer_id = cust.customer_id;

                    v_renewed_count := v_renewed_count + 1;
                ELSE
                    ROLLBACK TO before_customer_renewal;
                    UPDATE CUSTOMERS
                    SET membership_status = 'PENDING_PAYMENT'
                    WHERE customer_id = cust.customer_id;

                    v_failed_count := v_failed_count + 1;
                END IF;
            END;
        EXCEPTION
            WHEN OTHERS THEN
                -- Log individual errors for each failed renewal
                LOG_ACTIVITY(
                    cust.customer_id,
                    'RENEWAL',
                    'Error renewing customer ' || cust.customer_id || ': ' || SQLERRM,
                    SYS_CONTEXT('USERENV', 'IP_ADDRESS')
                );
                ROLLBACK TO before_customer_renewal;
                v_failed_count := v_failed_count + 1;
                DBMS_OUTPUT.PUT_LINE('Error renewing customer ' || cust.customer_id || ': ' || SUBSTR(SQLERRM, 1, 200));
        END;
    END LOOP;
    
    -- Log batch result
    LOG_ACTIVITY(
        NULL,                       -- use NULL for a batch operation
        'RENEWAL',                  -- activity type
        'Renewed ' || v_renewed_count || ' memberships, failed ' || v_failed_count,
        SYS_CONTEXT('USERENV','IP_ADDRESS')  -- optional for IP address
    );

    COMMIT;

    IF v_triggers_disabled THEN
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history ENABLE';
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers ENABLE';
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Warning: Could not re-enable triggers - ' || SUBSTR(SQLERRM, 1, 200));
        END;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Memberships renewed: ' || v_renewed_count);
    DBMS_OUTPUT.PUT_LINE('Renewal failures:    ' || v_failed_count);
EXCEPTION
    WHEN OTHERS THEN
        IF v_triggers_disabled THEN
            BEGIN
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history ENABLE';
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers ENABLE';
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END IF;
        ROLLBACK TO before_renewal_batch;
        DBMS_OUTPUT.PUT_LINE('Critical Error: ' || SUBSTR(SQLERRM, 1, 200));
        RAISE;
END;
/


--------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): EXECUTE PROC_RENEW_MEMBERSHIPS
--------------------------------------------------------------------------------
-- Expected Output:
-- - Memberships renewed: [count]
-- - Renewal failures: [count]
--------------------------------------------------------------------------------
BEGIN
    -- First create test data
    BEGIN
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance DISABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history DISABLE';
        
        -- Update some customers to have expired memberships
        UPDATE CUSTOMERS 
        SET membership_expiry_date = SYSDATE-10,
            membership_status = 'ACTIVE'
        WHERE customer_id IN (1001, 1002);
        
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history ENABLE';
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error setting up test data: ' || SQLERRM);
    END;
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING NORMAL RENEWAL ===');
    PROC_RENEW_MEMBERSHIPS(p_renewal_type => 'EXPIRED_ONLY');
END;
/

/*--------------------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): EXECUTE PROC_RENEW_MEMBERSHIPS
--------------------------------------------------------------------------------
-- Testing invalid renewal type and negative extension months
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID RENEWAL TYPE ===');
    BEGIN
        PROC_RENEW_MEMBERSHIPS(p_renewal_type => 'INVALID_TYPE');
        DBMS_OUTPUT.PUT_LINE('ERROR: Should not reach here with invalid type');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected error: ' || SUBSTR(SQLERRM, 1, 200));
    END;
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING NEGATIVE EXTENSION MONTHS ===');
    BEGIN
        PROC_RENEW_MEMBERSHIPS(p_extension_months => -5);
        DBMS_OUTPUT.PUT_LINE('ERROR: Should not reach here with negative months');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected error: ' || SUBSTR(SQLERRM, 1, 200));
    END;
END;
/ */


--------------------------------------------------------------------------------
-- PROCEDURE 2: PROC_EXPIRE_POINTS
--------------------------------------------------------------------------------
-- User Transaction:
-- Expire points that have reached their expiry date and mark them as expired.
-- Then evaluate whether affected customers still qualify for their current tier,
-- and downgrade their membership tier if necessary.

-- Purpose:
-- To maintain integrity of point balances and ensure customers are correctly tiered
-- based on their active points after expirations.

-- Input Arguments:
-- None
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PROC_EXPIRE_POINTS AS
    v_expired_count NUMBER := 0;
    v_customers_affected NUMBER := 0;
    v_tier_downgrades NUMBER := 0;
    v_start_time TIMESTAMP := SYSTIMESTAMP;
    v_batch_count NUMBER := 0;
    v_triggers_disabled BOOLEAN := FALSE;
BEGIN
    -- Disable triggers at start
    BEGIN
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance DISABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history DISABLE';
        EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers DISABLE';
        v_triggers_disabled := TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Warning: Could not disable triggers - ' || SUBSTR(SQLERRM, 1, 200));
    END;

    SAVEPOINT before_expiration_process;

    DBMS_OUTPUT.PUT_LINE('Starting points expiration at ' || TO_CHAR(v_start_time, 'YYYY-MM-DD HH24:MI:SS'));

    -- Process expiring points
    FOR exp_rec IN (
        SELECT pt.transaction_id, pt.customer_id, pt.points_amount, 
               c.name, c.tier_id, c.points_balance
        FROM POINT_TRANSACTIONS pt
        JOIN CUSTOMERS c ON pt.customer_id = c.customer_id
        WHERE pt.expiry_date <= TRUNC(SYSDATE)
          AND pt.points_amount > 0
          AND pt.transaction_type IN ('PURCHASE', 'BONUS')
          AND c.points_balance >= pt.points_amount  -- Ensure balance won't go negative
          AND NOT EXISTS (  -- Check if already expired
              SELECT 1 FROM POINT_TRANSACTIONS exp 
              WHERE exp.transaction_type = 'EXPIRY' 
              AND exp.description LIKE '%from transaction ' || pt.transaction_id || '%'
          )
        ORDER BY pt.customer_id, pt.expiry_date, pt.transaction_date
    ) LOOP
        BEGIN
            SAVEPOINT before_point_expiration;
            -- First verify the customer still has sufficient points
            DECLARE
                v_current_balance NUMBER;
            BEGIN
                SELECT points_balance INTO v_current_balance
                FROM CUSTOMERS
                WHERE customer_id = exp_rec.customer_id
                FOR UPDATE;

                

                IF v_current_balance < exp_rec.points_amount THEN
                    RAISE_APPLICATION_ERROR(-20003, 'Insufficient points balance for expiration');
                END IF;

                -- Create the negative transaction
                INSERT INTO POINT_TRANSACTIONS (
                    customer_id, 
                    points_amount, 
                    transaction_type, 
                    description, 
                    transaction_date
                ) VALUES (
                    exp_rec.customer_id, 
                    -exp_rec.points_amount, 
                    'EXPIRY', 
                    'Points expired from transaction ' || exp_rec.transaction_id,
                    SYSDATE
                );

                -- Update the customer's points balance to reflect the deduction
                UPDATE CUSTOMERS
                SET points_balance = points_balance - exp_rec.points_amount
                WHERE customer_id = exp_rec.customer_id;
                -- Add this after the customer balance update
                DBMS_OUTPUT.PUT_LINE('Updated customer ' || exp_rec.customer_id || 
                     ' from ' || v_current_balance || 
                     ' to ' || (v_current_balance - exp_rec.points_amount));

                -- Mark the original transaction as expired
                UPDATE POINT_TRANSACTIONS
                SET expiry_date = NULL,
                    description = description || ' - EXPIRED'
                WHERE transaction_id = exp_rec.transaction_id;

                v_expired_count := v_expired_count + exp_rec.points_amount;
                v_customers_affected := v_customers_affected + 1;
                v_batch_count := v_batch_count + 1;
            END;
        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO before_point_expiration;
                DBMS_OUTPUT.PUT_LINE('Error expiring points for TXN ' || exp_rec.transaction_id || ': ' || SUBSTR(SQLERRM, 1, 200));
        END;
    END LOOP;

    -- Process tier downgrades if needed
    DBMS_OUTPUT.PUT_LINE('Starting tier evaluation for ' || v_customers_affected || ' affected customers');
    
    FOR cust IN (
        SELECT DISTINCT pt.customer_id, c.name
        FROM POINT_TRANSACTIONS pt
        JOIN CUSTOMERS c ON pt.customer_id = c.customer_id
        WHERE pt.transaction_type = 'EXPIRY'
          AND TRUNC(pt.transaction_date) = TRUNC(SYSDATE)
    ) LOOP
        BEGIN
            SAVEPOINT before_tier_evaluation;

            DECLARE
                v_current_tier NUMBER;
                v_current_points NUMBER;
                v_qualified_tier NUMBER;
                v_current_tier_name VARCHAR2(50);
                v_new_tier_name VARCHAR2(50);
            BEGIN
                -- Get current tier info with FOR UPDATE
                SELECT c.tier_id, c.points_balance, mt.tier_name
                INTO v_current_tier, v_current_points, v_current_tier_name
                FROM CUSTOMERS c
                JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
                WHERE c.customer_id = cust.customer_id
                FOR UPDATE;

                -- Find the highest tier the customer qualifies for
                SELECT MAX(mt.tier_id), MAX(mt.tier_name)
                INTO v_qualified_tier, v_new_tier_name
                FROM MEMBERSHIP_TIERS mt
                WHERE mt.points_required <= v_current_points;

                -- Downgrade if needed
                IF v_qualified_tier < v_current_tier THEN
                    UPDATE CUSTOMERS
                    SET tier_id = v_qualified_tier
                    WHERE customer_id = cust.customer_id;

                    v_tier_downgrades := v_tier_downgrades + 1;
                    DBMS_OUTPUT.PUT_LINE('Downgraded ' || cust.name || ' from ' || v_current_tier_name || ' to ' || v_new_tier_name);
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    ROLLBACK TO before_tier_evaluation;
                    DBMS_OUTPUT.PUT_LINE('Tier data not found for ' || cust.name);
            END;
        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO before_tier_evaluation;
                DBMS_OUTPUT.PUT_LINE('Error evaluating tier for ' || cust.name || ': ' || SUBSTR(SQLERRM, 1, 200));
        END;
    END LOOP;

    -- Log Activity
    LOG_ACTIVITY(
        NULL,                         -- batch operation
        'EXPIRATION',
        'Expired ' || v_expired_count || ' points for ' || v_customers_affected
          || ' customers, ' || v_tier_downgrades || ' downgrades.',
        SYS_CONTEXT('USERENV','IP_ADDRESS')
    );

    COMMIT;

    -- Re-enable triggers if they were disabled
    IF v_triggers_disabled THEN
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history ENABLE';
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers ENABLE';
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Warning: Could not re-enable triggers - ' || SUBSTR(SQLERRM, 1, 200));
        END;
    END IF;

    DBMS_OUTPUT.PUT_LINE('----------------------------------');
    DBMS_OUTPUT.PUT_LINE('Points expiration completed at ' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Total processing time: ' || EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start_time)) || ' seconds');
    DBMS_OUTPUT.PUT_LINE('Results:');
    DBMS_OUTPUT.PUT_LINE('- Points expired: ' || v_expired_count);
    DBMS_OUTPUT.PUT_LINE('- Customers affected: ' || v_customers_affected);
    

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO before_expiration_process;
        -- Ensure triggers are re-enabled if they were disabled
        IF v_triggers_disabled THEN
            BEGIN
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_membership_history ENABLE';
                EXECUTE IMMEDIATE 'ALTER TRIGGER trg_auto_assign_vouchers ENABLE';
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
        DBMS_OUTPUT.PUT_LINE('CRITICAL ERROR in PROC_EXPIRE_POINTS: ' || SUBSTR(SQLERRM, 1, 200));
        DBMS_OUTPUT.PUT_LINE('Entire operation rolled back. No changes committed.');
        RAISE;
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): EXECUTE PROC_EXPIRE_POINTS
--------------------------------------------------------------------------------
-- Insert test point transactions that should expire
INSERT INTO POINT_TRANSACTIONS (
    customer_id, points_amount, transaction_type, 
    description, transaction_date, expiry_date
) 
SELECT 
    customer_id, 
    100, 
    'PURCHASE', 
    'Test expiring points', 
    SYSDATE-60, 
    SYSDATE-1
FROM CUSTOMERS 
WHERE customer_id IN (1001, 1002, 1003);

COMMIT;

-- Execute the procedure with trigger disabled
BEGIN
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance DISABLE';
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING NORMAL POINT EXPIRATION ===');
    PROC_EXPIRE_POINTS;
    
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
EXCEPTION
    WHEN OTHERS THEN
        BEGIN
            EXECUTE IMMEDIATE 'ALTER TRIGGER trg_sync_point_balance ENABLE';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        RAISE;
END;
/


-- Verify points were expired

SELECT c.customer_id, c.name, c.points_balance, 
       (SELECT SUM(points_amount) FROM POINT_TRANSACTIONS pt 
        WHERE pt.customer_id = c.customer_id) AS total_points
FROM CUSTOMERS c
WHERE customer_id IN (1001, 1002, 1003);

-- Verify expired transactions were marked
SELECT transaction_id, customer_id, points_amount, 
       transaction_type, description, expiry_date
FROM POINT_TRANSACTIONS
WHERE description LIKE '%Test expiring points%';

-- Check for tier downgrades if applicable 
SELECT mh.customer_id, c.name, 
       old_t.tier_name AS old_tier, 
       new_t.tier_name AS new_tier,
       mh.change_date, mh.change_reason
FROM MEMBERSHIP_HISTORY mh
JOIN CUSTOMERS c ON mh.customer_id = c.customer_id
JOIN MEMBERSHIP_TIERS old_t ON mh.old_tier_id = old_t.tier_id
JOIN MEMBERSHIP_TIERS new_t ON mh.new_tier_id = new_t.tier_id
WHERE mh.change_date >= TRUNC(SYSDATE)
ORDER BY mh.change_date DESC;


--Expected output:
/* 
=== TESTING NORMAL POINT EXPIRATION ===
Starting points expiration at 2025-04-28 19:36:50
Updated customer 1001 from 400 to 300
Updated customer 1002 from 850 to 750
Updated customer 1003 from 1100 to 1000
Updated customer 1006 from 500 to 400
Starting tier evaluation for 4 affected customers
----------------------------------
Points expiration completed at 2025-04-28 19:36:50
Total processing time: .096 seconds
Results:
- Points expired: 400
- Customers affected: 4

PL/SQL procedure successfully completed.
*/


--Expected Verification
/* 
CUSTOMER_ID NAME                                                                                             POINTS_BALANCE TOTAL_POINTS
----------- ---------------------------------------------------------------------------------------------------- -------------- ------------
       1001 John Smith                                                                                          300     0
       1002 Emily Johnson                                                                                       750     0
       1003 Michael Lee                                                                                        1000     0


TRANSACTION_ID CUSTOMER_ID POINTS_AMOUNT TRANSACTION_TYPE
-------------- ----------- ------------- --------------------
DESCRIPTION
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EXPIRY_DA
---------
             6        1001           100 PURCHASE
Test expiring points - EXPIRED


             7        1002           100 PURCHASE
Test expiring points - EXPIRED


             8        1003           100 PURCHASE
Test expiring points - EXPIRED




CUSTOMER_ID NAME                                                                                             OLD_TIER              NEW_TIER
----------- ---------------------------------------------------------------------------------------------------- -------------------- --------------------
CHANGE_DATE                                                                 CHANGE_REASON
--------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
       1003 Michael Lee                                                                                      Gold                  Silver
28-APR-25 07.36.50.656000 PM                                                DOWNGRADE

       1005 David Wong                                                                                       Bronze        Gold
28-APR-25 07.36.49.236000 PM                                                ADMIN

       1003 Michael Lee                                                                                      Bronze        Silver
28-APR-25 07.36.49.220000 PM                                                ADMIN


*/

/*
--------------------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): EXECUTE PROC_EXPIRE_POINTS
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING WITH LOCKED RECORDS ===');
    DECLARE
        v_test_cust_id NUMBER;
    BEGIN
        -- Lock a customer record TO GET THE ERROR TEST
        SELECT customer_id INTO v_test_cust_id FROM CUSTOMERS WHERE ROWNUM = 1 FOR UPDATE;
        
        -- Try to expire points while records are locked
        -- SHOULD BE NO RECORD
        
        PROC_EXPIRE_POINTS;
        COMMIT; -- Release the lock
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected NOTHING ENTER HERE');
            ROLLBACK;
    END;
END;
/


--EXPECTED ERROR:
/*
It will Skip the locked record, causing no points to be expired.
Encounter a lock wait condition or deadlock, which would prevent the procedure from processing the record until the lock is released.
*/

-- Expected verification: no record changes
-- Verify points were expired
SELECT c.customer_id, c.name, c.points_balance, 
       (SELECT SUM(points_amount) FROM POINT_TRANSACTIONS pt 
        WHERE pt.customer_id = c.customer_id) AS total_points
FROM CUSTOMERS c
WHERE customer_id IN (1001, 1002, 1003);

-- Verify expired transactions were marked
SELECT transaction_id, customer_id, points_amount, 
       transaction_type, description, expiry_date
FROM POINT_TRANSACTIONS
WHERE description LIKE '%Test expiring points%';

-- Check for tier downgrades if applicable
SELECT mh.customer_id, c.name, 
       old_t.tier_name AS old_tier, 
       new_t.tier_name AS new_tier,
       mh.change_date, mh.change_reason
FROM MEMBERSHIP_HISTORY mh
JOIN CUSTOMERS c ON mh.customer_id = c.customer_id
JOIN MEMBERSHIP_TIERS old_t ON mh.old_tier_id = old_t.tier_id
JOIN MEMBERSHIP_TIERS new_t ON mh.new_tier_id = new_t.tier_id
WHERE mh.change_date >= TRUNC(SYSDATE)
ORDER BY mh.change_date DESC;

*/

--------------------------------------------------------------------------------
-- FUNCTION 1: FN_CALC_UPGRADE_VALUE
--------------------------------------------------------------------------------
-- User Transaction:
-- Check how much a customer would benefit from upgrading to the next membership tier,
-- including discount percentage increase, points needed, and fee difference.

-- User Transaction Type: Personalized Upgrade Recommendation
-- Typical User: Customer considering tier benefits or staff advising on upgrades
-- Transaction Flow: 
-- User views tier benefits in profile/checkout
-- System calls FN_CALC_UPGRADE_VALUE(customer_id)
-- Returns formatted message like:
--"Upgrade to Silver | Discount Increase: +5% | Points Needed: 200 | Renewal Fee Change: +$5"

-- Purpose:
-- To provide an informative message comparing the customer's current tier with the next one.

-- Input Arguments:
-- p_customer_id  NUMBER   the ID of the customer to evaluate

-- Return:
-- VARCHAR2  summary string showing potential upgrade benefit or status
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION FN_CALC_UPGRADE_VALUE (
    p_customer_id IN NUMBER
) RETURN VARCHAR2 AS
    v_result VARCHAR2(1000);
BEGIN
    SELECT 
        'Upgrade to ' || next_tier.tier_name || 
        ' | Discount Increase: +' || (next_tier.discount_percentage - current_tier.discount_percentage) || '%' ||
        ' | Points Needed: ' || (next_tier.points_required - c.points_balance) ||
        ' | Renewal Fee Change: ' || 
            CASE 
                WHEN next_tier.renewal_fee > current_tier.renewal_fee THEN '+$' || (next_tier.renewal_fee - current_tier.renewal_fee)
                WHEN next_tier.renewal_fee < current_tier.renewal_fee THEN '-$' || (current_tier.renewal_fee - next_tier.renewal_fee)
                ELSE 'No change'
            END
    INTO v_result
    FROM CUSTOMERS c
    JOIN MEMBERSHIP_TIERS current_tier ON c.tier_id = current_tier.tier_id
    JOIN MEMBERSHIP_TIERS next_tier ON next_tier.tier_id = current_tier.tier_id + 1
    WHERE c.customer_id = p_customer_id;

    LOG_ACTIVITY(
        p_customer_id,
        'TIER_CHANGE',  -- activity type is TIER_CHANGE for this case
        'Calculated upgrade for customer ' || p_customer_id || ': ' || v_result,
        SYS_CONTEXT('USERENV', 'IP_ADDRESS')  -- optional: captures the client IP address
    );


    RETURN v_result;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
    
        RETURN 'At highest tier or invalid customer';
        
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): FN_CALC_UPGRADE_VALUE
--------------------------------------------------------------------------------
-- Expected Output:
-- - Descriptive upgrade message with discount, fee, and points gap
-- === TESTING UPGRADE CALCULATION ===
-- Upgrade to Silver | Discount Increase: +5% | Points Needed: 200 | Renewal Fee Change: +$5
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING UPGRADE CALCULATION ===');
    DBMS_OUTPUT.PUT_LINE(FN_CALC_UPGRADE_VALUE(1001));
END;
/

/*--------------------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): FN_CALC_UPGRADE_VALUE
--------------------------------------------------------------------------------
-- Testing with invalid customer ID and highest tier customer
--Expected Output: At highest tier or invalid customer

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID CUSTOMER ID ===');
    DBMS_OUTPUT.PUT_LINE(FN_CALC_UPGRADE_VALUE(9999));
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING HIGHEST TIER CUSTOMER ===');
    DBMS_OUTPUT.PUT_LINE(FN_CALC_UPGRADE_VALUE(1005));
END;
/ */

--------------------------------------------------------------------------------
-- FUNCTION 2: FN_CHECK_MEMBERSHIP_HEALTH 
--------------------------------------------------------------------------------
-- User Transaction:
-- Check how close a customer's membership is to expiring or whether it's overdue,
-- and return a health status message including tier and last renewal info.

-- Purpose:
-- To return a readable status about the customer's membership health and urgency.

-- User Transaction Type: Customer Self-Service Inquiry
-- Typical User: Customer or frontline staff assisting a specific customer
-- Transaction Flow:
-- Customer accesses their profile (web/mobile/app)
-- System calls FN_CHECK_MEMBERSHIP_HEALTH(customer_id)
-- Returns a single human-readable status message like:
--"Silver membership: CRITICAL - renew in 3 days"

-- Input Arguments:
-- p_customer_id  NUMBER   the ID of the customer

-- Return:
-- VARCHAR2  description of the customer's current membership status
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION FN_CHECK_MEMBERSHIP_HEALTH (
    p_customer_id IN NUMBER
) RETURN VARCHAR2 AS
    v_status VARCHAR2(200);
    v_expiry_days NUMBER;
    v_last_renewal DATE;
    v_tier_name VARCHAR2(50);
BEGIN
    SELECT 
        FLOOR(membership_expiry_date - SYSDATE),
        membership_status,
        last_renewal_date,
        mt.tier_name
    INTO 
        v_expiry_days,
        v_status,
        v_last_renewal,
        v_tier_name
    FROM CUSTOMERS c
    JOIN MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
    WHERE customer_id = p_customer_id;

    RETURN 
        v_tier_name || ' membership: ' ||
        CASE 
            WHEN v_status != 'ACTIVE' THEN v_status || ' (last renewed: ' || TO_CHAR(v_last_renewal, 'DD-MON-YYYY') || ')'
            WHEN v_expiry_days <= 0 THEN 'EXPIRED ' || ABS(v_expiry_days) || ' days ago'
            WHEN v_expiry_days <= 7 THEN 'CRITICAL - renew in ' || v_expiry_days || ' days'
            WHEN v_expiry_days <= 30 THEN 'Renewal due in ' || v_expiry_days || ' days'
            ELSE 'Active (expires in ' || v_expiry_days || ' days)'
        END;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'Customer not found';
    WHEN OTHERS THEN
        RETURN 'Error checking status: ' || SUBSTR(SQLERRM, 1, 100);
END;
/

--------------------------------------------------------------------------------
-- DEMO TEST 1 (NORMAL CASE): FN_CHECK_MEMBERSHIP_HEALTH
--------------------------------------------------------------------------------
-- Expected Output:
-- Status like "Active", "Expired X days ago", "Renewal due in Y days"
-- Output: Bronze membership: Active (expires in 364 days)
--------------------------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING MEMBERSHIP HEALTH ===');
    DBMS_OUTPUT.PUT_LINE(FN_CHECK_MEMBERSHIP_HEALTH(1001));
END;
/

/*
--------------------------------------------------------------------------------
-- DEMO TEST 2 (ERROR CASE): FN_CHECK_MEMBERSHIP_HEALTH
--------------------------------------------------------------------------------
-- Testing with invalid customer ID and expired membership
-- Expected Output: Customer not found

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID CUSTOMER ID ===');
    DBMS_OUTPUT.PUT_LINE(FN_CHECK_MEMBERSHIP_HEALTH(9999));
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING EXPIRED MEMBERSHIP ===');
    -- Test with existing test customer (1016)
    DBMS_OUTPUT.PUT_LINE(FN_CHECK_MEMBERSHIP_HEALTH(1016));
END;
/

*/


--------------------------------------------------------------------------------
-- FUNTIONS are different USER TRANSACTIONS with the QUERIES
--------------------------------------------------------------------------------
/*
Scenario 1: HOW THE FUNCTIONS WORK TOGETHER
User: Customer John Smith
Goal: Check membership status 
User use Mobile App Calls FN_CHECK_MEMBERSHIP_HEALTH
Output: "Bronze membership: URGENT - renew in 12 days" 
Then, user ask for Upgrade Suggestion Called by FN_CALC_UPGRADE_VALUE: 
Output: "Upgrade to Silver | Discount Increase: +5% | Points Needed: 200 | Renewal Fee Change: +$5"  

Scenario 2: HOW QUERY UPCOMING RENEWAL Different from FN_CHECK_MEMBERSHIP_HEALTH
Use in Administrative Batch Processing, thus if a Staff act as User: Membership Manager Sarah
Goal: Prepare for upcoming renewals
Sarah exports this to Excel to plan renewal campaigns. Batch Renewal Processing via called the PROC_RENEW_MEMBERSHIPS procedure. Output: "Memberships renewed: 42, Renewal failures: 3"

Scenario 3:HOW QUERY TIER COMPARISON Different from FN_CALC_UPGRADE_VALUE
Use as Analytical Review (in Management)
if a Staff act a User: Marketing Director David
Goal: Analyze tier distribution  
David Run Tier Comparison Query and Uses query results to:
1. Identify 1,200 customers near tier thresholds
2. Allocate budget for targeted promotional
3. Adjust point requirements for underperforming tiers

*/




--------------------------------------------------------------------------------
-- QUERY 1: UPCOMING RENEWALS
--------------------------------------------------------------------------------
-- User Transaction:
-- Display a list of all customers whose memberships are about to expire within the next
-- 30 days, including those already expired. Show customer name, email, tier, expiry date,
-- days until expiry, and renewal fee. Useful for membership management or notifying users.

-- Purpose:
-- To retrieve and classify members into categories like EXPIRED, URGENT, UPCOMING, or ACTIVE
-- based on how soon their memberships are expiring.

-- User Transaction Type: Administrative Batch Processing
-- Typical User: Membership manager or automated renewal system
-- Transaction Flow:
--Staff runs "Renewals Due" report (or automated job executes)
--Query returns tabular data of all expiring memberships

--Used to:
--Generate renewal notices
--Allocate staff for renewal calls
--Forecast cash flow from renewal fees
--------------------------------------------------------------------------------

SELECT 
    c.customer_id,
    c.name,
    c.email,
    mt.tier_name,
    c.membership_expiry_date,
    FLOOR(c.membership_expiry_date - SYSDATE) AS days_until_expiry,
    mt.renewal_fee,
    CASE 
        WHEN c.membership_expiry_date <= SYSDATE THEN 'EXPIRED'
        WHEN c.membership_expiry_date <= SYSDATE + 7 THEN 'URGENT'
        WHEN c.membership_expiry_date <= SYSDATE + 30 THEN 'UPCOMING'
        ELSE 'ACTIVE'
    END AS renewal_status
FROM 
    CUSTOMERS c
JOIN 
    MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
WHERE 
    c.is_member = 'Y'
ORDER BY 
    c.membership_expiry_date;

--------------------------------------------------------------------------------
-- DEMO TEST (NORMAL CASE): UPCOMING RENEWALS
--------------------------------------------------------------------------------
-- Expected Output:
-- - List of customers with expiring memberships within 30 days
-- - Includes their tier, fee, and days until expiry
--------------------------------------------------------------------------------
/*

CUSTOMER_ID NAME
----------- ----------------------------------------------------------------------------------------------------
EMAIL                                                                                                TIER_NAME                 MEMBERSHI DAYS_UNTIL_EXPIRY RENEWAL_FEE RENEWAL_
---------------------------------------------------------------------------------------------------- -------------------- --------- ----------------- ----------- --------
       1003 Michael Lee
mikelee@example.com                                                                                  Silver   10-JAN-26                256          15 ACTIVE

       1004 Sarah Tan
saraht@example.com                                                                                   Platinum  28-FEB-26               305          25 ACTIVE

       1005 David Wong
davidw@example.com                                                                                   Diamond  05-MAR-26                310          30 ACTIVE

       1002 Emily Johnson
emilyj@example.com                                                                                   Silver   28-APR-26                364          15 ACTIVE

       1006 Test User for G001
test.user@example.com                                                                                Bronze   28-APR-26                364          10 ACTIVE

       1001 John Smith
johnsmith@example.com                                                                                Bronze   28-APR-26                364          10 ACTIVE


6 rows selected.


*/
--------------------------------------------------------------------------------
-- QUERY 2: TIER COMPARISON FOR A CUSTOMER
--------------------------------------------------------------------------------
-- User Transaction:
-- Retrieve the data from CUSTOMERS and MEMBERSHIP_TIERS, to compare the current tier of a customer with the next tier to determine upgrade eligibility.
-- Includes calculating how many more points are needed, the discount difference, and the change in renewal fee. 

-- User Transaction Type: Membership Tier Analysis
--Typical User: Marketing team or business analysts
--Transaction Flow:
--Analyst investigates tier distribution
--Runs query with specific customer filter
--Gets structured data showing:
--Current vs next tier metrics
--Points gap analysis
--Eligibility status flags

-- Purpose:
-- To provide tier upgrade insight by comparing a customer's current points balance
-- with the requirements of the next tier.
--------------------------------------------------------------------------------

SELECT 
    c.customer_id,
    c.name,
    curr.tier_name AS current_tier,
    c.points_balance,
    next.tier_name AS next_tier,
    next.points_required - c.points_balance AS points_needed,
    next.discount_percentage - curr.discount_percentage AS additional_discount,
    next.renewal_fee - curr.renewal_fee AS fee_change,
    CASE 
        WHEN next.tier_id IS NULL THEN 'MAX_TIER'
        WHEN c.points_balance >= next.points_required THEN 'ELIGIBLE_NOW'
        ELSE 'NEEDS_MORE_POINTS'
    END AS upgrade_status
FROM 
    CUSTOMERS c
JOIN 
    MEMBERSHIP_TIERS curr ON c.tier_id = curr.tier_id
LEFT JOIN 
    MEMBERSHIP_TIERS next ON next.tier_id = curr.tier_id + 1
WHERE 
    c.customer_id = 1001;

--------------------------------------------------------------------------------
-- DEMO TEST (NORMAL CASE): TIER COMPARISON
--------------------------------------------------------------------------------
-- Expected Output:
-- - Displays comparison of current vs. next tier, points gap, and potential benefits
--------------------------------------------------------------------------------
/*
CUSTOMER_ID NAME                                                                                             CURRENT_TIER          POINTS_BALANCE NEXT_TIER            POINTS_NEEDED
----------- ---------------------------------------------------------------------------------------------------- -------------------- -------------- -------------------- -------------
ADDITIONAL_DISCOUNT FEE_CHANGE UPGRADE_STATUS
------------------- ---------- -----------------
       1001 John Smith                                                                                       Bronze                   300 Silver                         200
                  5          5 NEEDS_MORE_POINTS

*/
--------------------------------------------------------------------------------
-- TEST CASE 1:  TEST POINT EARNING AND TIER VERIFICATION
--------------------------------------------------------------------------------
-- User Transaction:
-- This test simulates the awarding of additional points to a customer,
-- and then checks if the new point balance results in a tier upgrade. 
-- It verifies that triggers update the customer's tier and assign rewards accordingly.

-- Purpose:
-- To validate the system behavior when a customer earns enough points to trigger an automatic
-- membership tier upgrade and logs this in the membership history.
--------------------------------------------------------------------------------
PROMPT ===== TEST CASE 1   =====
-- First, let's verify the current tier points requirements
PROMPT ===== Tier Requirement  =====
SELECT tier_id, tier_name, points_required 
FROM MEMBERSHIP_TIERS 
ORDER BY tier_id;

PROMPT =====  Initial Customer Status  =====
-- Check the customer's current status before adding point 
-- Current Status: After the above expiration test case, Customer 1001 starts in the Bronze tier with 300 points and needs 200 more to reach Silver. 
SELECT 
    c.customer_id,
    c.name,
    c.points_balance,
    mt.tier_name AS current_tier,
    mt.points_required AS current_tier_requirement,
    next_t.tier_name AS next_tier,
    next_t.points_required AS next_tier_requirement,
    next_t.points_required - c.points_balance AS points_needed
FROM 
    CUSTOMERS c
JOIN 
    MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
LEFT JOIN 
    MEMBERSHIP_TIERS next_t ON next_t.tier_id = mt.tier_id + 1
WHERE 
    c.customer_id = 1001;


PROMPT =====  Use Function FN_CALC_UPGRADE_VALUE =====
-- Current Status: Customer 1001 starts in the Bronze tier with 300 points and needs 200 more to reach Silver. 
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING UPGRADE CALCULATION ===');
    DBMS_OUTPUT.PUT_LINE(FN_CALC_UPGRADE_VALUE(1001));
END;
/

PROMPT =====  Use Function FN_CHECK_MEMBERSHIP_HEALTH =====
-- Current Status: Membership is Active, Bronze membership: Active (expires in 365 days)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING MEMBERSHIP HEALTH ===');
    DBMS_OUTPUT.PUT_LINE(FN_CHECK_MEMBERSHIP_HEALTH(1001));
END;
/

-- Hence, we can continue to Add Point and upgrade the Tier
-- If the tier didn't upgrade automatically, we need to:
-- 1. Verify the trigger is working
-- 2. Manually update if needed


 
PROMPT =====  Trigger Status =====
-- First, let's check if the trigger is enabled and working
SELECT trigger_name, status 
FROM user_triggers 
WHERE trigger_name = 'TRG_SYNC_POINT_BALANCE';

-- If the trigger is disabled, enable it
ALTER TRIGGER trg_sync_point_balance ENABLE;


PROMPT =====  Add Point =====
-- Now let's simulate the point addition again with triggers enabled
BEGIN
    DBMS_OUTPUT.PUT_LINE('Adding 500 points to customer 1001 with triggers enabled...');
    INSERT INTO POINT_TRANSACTIONS 
      (customer_id, points_amount, transaction_type, description) 
    VALUES 
      (1001, 500, 'PURCHASE', 'Test points addition - with triggers');
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Successfully added 500 points to customer 1001');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error adding points: ' || SQLERRM);
        ROLLBACK;
END;
/


PROMPT =====  Checked Customer Status - Tier upgraded =====
-- Verify the upgrade occurred
SELECT 
    c.customer_id,
    c.name,
    c.points_balance,
    mt.tier_name AS current_tier,
    (SELECT points_required FROM MEMBERSHIP_TIERS WHERE tier_id = mt.tier_id + 1) - c.points_balance AS points_needed_for_next_tier
FROM 
    CUSTOMERS c
JOIN 
    MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
WHERE 
    customer_id = 1001;

/*
=====  Checked Customer Status - Tier upgraded =====

CUSTOMER_ID NAME                                                                                             POINTS_BALANCE CURRENT_TIER          POINTS_NEEDED_FOR_NEXT_TIER
----------- ---------------------------------------------------------------------------------------------------- -------------- -------------------- ---------------------------
       1001 John Smith                                                                                          800 Silver                                        700


*/

PROMPT =====   Membership History Logs =====
-- Check the membership history for the upgrade
SELECT mh.change_date, mh.change_reason, 
       old_t.tier_name AS old_tier, 
       new_t.tier_name AS new_tier
FROM MEMBERSHIP_HISTORY mh
JOIN MEMBERSHIP_TIERS old_t ON mh.old_tier_id = old_t.tier_id
JOIN MEMBERSHIP_TIERS new_t ON mh.new_tier_id = new_t.tier_id
WHERE mh.customer_id = 1001
ORDER BY mh.change_date DESC;

/*=====   Membership History Logs =====

CHANGE_DATE                                                                 CHANGE_REASON                    OLD_TIER
--------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------- --------------------
NEW_TIER
--------------------
28-APR-25 07.20.20.883000 PM                                                UPGRADE                          Bronze
Silver

*/

-- If the automatic upgrade still didn't occur, we can manually update the tier
DECLARE
    v_new_tier_id NUMBER;
    v_old_tier_id NUMBER;
BEGIN
    -- Get the current tier first
    SELECT tier_id INTO v_old_tier_id
    FROM CUSTOMERS 
    WHERE customer_id = 1001;
    
    -- Find the appropriate tier for the customer's current points
    SELECT MAX(tier_id) INTO v_new_tier_id
    FROM MEMBERSHIP_TIERS
    WHERE points_required <= (SELECT points_balance FROM CUSTOMERS WHERE customer_id = 1001);
    
    -- Only proceed if there's actually a tier change
    IF v_new_tier_id != v_old_tier_id THEN
        -- Update the customer's tier
        UPDATE CUSTOMERS
        SET tier_id = v_new_tier_id
        WHERE customer_id = 1001;
        
        -- Log the tier change
        INSERT INTO MEMBERSHIP_HISTORY (
            customer_id, 
            old_tier_id, 
            new_tier_id, 
            change_date, 
            change_reason
        )
        VALUES (
            1001,
            v_old_tier_id,
            v_new_tier_id,
            SYSDATE,
            'MANUAL UPGRADE'
        );
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Manually updated customer 1001 from tier ' || 
                            v_old_tier_id || ' to tier ' || v_new_tier_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('No Manually Updated tier needed - customer already at appropriate tier, Automatically Upgraded Tier Successfully.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in manual tier update: ' || SQLERRM);
        ROLLBACK;
END;
/ 

-- output:No Manually Updated tier needed - customer already at appropriate tier, Automatically Upgraded Tier Successfully.
PROMPT => TRIGGER trg_membership_history WORKING <=

-- Final verification
SELECT 
    c.customer_id,
    c.name,
    c.points_balance,
    mt.tier_name AS current_tier
FROM 
    CUSTOMERS c
JOIN 
    MEMBERSHIP_TIERS mt ON c.tier_id = mt.tier_id
WHERE 
    customer_id = 1001;

/*output:
CUSTOMER_ID NAME                                                                                             POINTS_BALANCE CURRENT_TIER
----------- ---------------------------------------------------------------------------------------------------- -------------- --------------------
       1001 John Smith                                                                                          800 Silver

*/

/*
--------------------------------------------------------------------------------
-- TEST POINT EARNING ERROR CASES
--------------------------------------------------------------------------------
-- Testing invalid point additions and trigger behavior
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== TESTING NEGATIVE POINT ADDITION ===');
    BEGIN
        INSERT INTO POINT_TRANSACTIONS 
          (customer_id, points_amount, transaction_type, description) 
        VALUES 
          (1001, -100, 'PURCHASE', 'Invalid negative points');
        DBMS_OUTPUT.PUT_LINE('ERROR: Should not reach here with negative points');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected error: ' || SUBSTR(SQLERRM, 1, 200));
            ROLLBACK;
    END;
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING INVALID TRANSACTION TYPE ===');
    BEGIN
        INSERT INTO POINT_TRANSACTIONS 
          (customer_id, points_amount, transaction_type, description) 
        VALUES 
          (1001, 100, 'INVALID_TYPE', 'Invalid transaction type');
        DBMS_OUTPUT.PUT_LINE('ERROR: Should not reach here with invalid type');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected error: ' || SUBSTR(SQLERRM, 1, 200));
            ROLLBACK;
    END;
    
    DBMS_OUTPUT.PUT_LINE('=== TESTING NON-EXISTENT CUSTOMER ===');
    BEGIN
        INSERT INTO POINT_TRANSACTIONS 
          (customer_id, points_amount, transaction_type, description) 
        VALUES 
          (9999, 100, 'PURCHASE', 'Non-existent customer');
        DBMS_OUTPUT.PUT_LINE('ERROR: Should not reach here with invalid customer');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Expected error: ' || SUBSTR(SQLERRM, 1, 200));
            ROLLBACK;
    END;
END;
/ 

/*expected output: === TESTING NEGATIVE POINT ADDITION ===
Expected error: ORA-02290: check constraint (SYSTEM.CHK_POINTS_AMOUNT) violated
=== TESTING INVALID TRANSACTION TYPE ===
Expected error: ORA-02290: check constraint (SYSTEM.SYS_C0026292) violated
=== TESTING NON-EXISTENT CUSTOMER ===
Expected error: ORA-02291: integrity constraint (SYSTEM.FK_PT_CUSTOMER) violated - parent key not found*/
*/

PROMPT ===== END TEST CASE 1 =====

--------------------------------------------------------------------------------
-- FINAL SECTION: SCRIPT COMPLETION REMARKS
--------------------------------------------------------------------------------
-- This script demonstrates the key components of a Membership Management System,
-- including procedures for processing renewals and point expirations, functions
-- for upgrade evaluation and health checks, and queries for tier analysis and
-- status verification.

-- All modules have been tested through realistic demo scenarios. Additional tests
-- or enhancements may be added depending on future requirements, such as user-facing
-- interfaces or monthly automation jobs.
--------------------------------------------------------------------------------
-- END OF SCRIPT
--------------------------------------------------------------------------------


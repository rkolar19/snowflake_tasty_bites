-- Verify that order totals are not less than order amounts (pre-tax)
-- Catches data integrity issues where discounts exceed order value
select ORDER_ID, ORDER_AMOUNT, ORDER_TOTAL
from {{ source('tb_101', 'ORDER_HEADER') }}
where ORDER_TOTAL < ORDER_AMOUNT
  and ORDER_DISCOUNT_AMOUNT is null

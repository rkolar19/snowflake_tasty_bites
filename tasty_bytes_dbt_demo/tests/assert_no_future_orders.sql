-- Verify that no orders exist in the future
-- Catches timestamp data quality issues
select ORDER_ID, ORDER_TS
from {{ source('tb_101', 'ORDER_HEADER') }}
where ORDER_TS > current_timestamp()

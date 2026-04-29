-- Verify that mart models produce rows after build
-- Catches empty table issues from broken upstream dependencies
select 'orders' as model_name, count(*) as row_count
from {{ ref('orders') }}
having count(*) = 0

union all

select 'customer_loyalty_metrics', count(*)
from {{ ref('customer_loyalty_metrics') }}
having count(*) = 0

union all

select 'sales_data_by_truck', count(*)
from {{ ref('sales_data_by_truck') }}
having count(*) = 0

-- Verify that all orders have valid location references
-- Catches broken foreign key relationships between orders and locations
select oh.ORDER_ID, oh.LOCATION_ID
from {{ source('tb_101', 'ORDER_HEADER') }} oh
left join {{ source('tb_101', 'LOCATION') }} loc
    on oh.LOCATION_ID = loc.LOCATION_ID
where loc.LOCATION_ID is null
  and oh.LOCATION_ID is not null

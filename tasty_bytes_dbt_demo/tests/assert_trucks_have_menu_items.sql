-- Verify that every truck has at least one menu item assigned
-- Catches trucks with no menu configuration
select t.TRUCK_ID
from {{ source('tb_101', 'TRUCK') }} t
left join {{ source('tb_101', 'MENU') }} m
    on t.MENU_TYPE_ID = m.MENU_TYPE_ID
where m.MENU_ID is null

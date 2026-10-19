select c.id as customer_id, c.tier, count(o.id) as order_count
from customers c
left join orders o on o.customer_id = c.id
group by c.id

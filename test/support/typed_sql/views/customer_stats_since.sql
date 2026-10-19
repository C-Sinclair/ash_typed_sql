select c.id as customer_id, c.name, count(o.id) as order_count
from customers c
left join orders o on o.customer_id = c.id and o.inserted_at >= $1
group by c.id

select c.id as customer_id, c.name, c.email, count(o.id) as order_count, sum(o.total) as lifetime_value
from customers c
left join orders o on o.customer_id = c.id
group by c.id

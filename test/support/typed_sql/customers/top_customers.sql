select c.id, c.name, c.email, c.tier, c.tags, sum(o.total) as lifetime_value
from customers c
join orders o on o.customer_id = c.id
where o.inserted_at > $1
group by c.id
order by lifetime_value desc
limit $2

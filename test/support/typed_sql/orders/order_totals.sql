select id, total, discount, shipped_at, total * 2 as doubled, total * 3 as tripled
from orders
order by id

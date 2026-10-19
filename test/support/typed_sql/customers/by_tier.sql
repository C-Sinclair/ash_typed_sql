select id, name, active, settings, born_on, tier
from customers
where tier = $1
order by name

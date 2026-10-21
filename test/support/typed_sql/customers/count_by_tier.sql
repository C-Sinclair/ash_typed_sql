select count(*) as total
from customers
where tier = $1

select borrower, count(*) as loan_count
from loans
group by borrower
order by loan_count desc, borrower
limit $1

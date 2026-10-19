select b.id as book_id, b.title, count(l.id) as loan_count
from shelf.books b
left join shelf.loans l on l.book_id = b.id and l.borrowed_on >= $1
group by b.id, b.title

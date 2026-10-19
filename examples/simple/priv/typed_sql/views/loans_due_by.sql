select l.id as loan_id, l.book_id, l.borrower, l.due_on
from loans l
where l.returned_on is null and l.due_on <= $1

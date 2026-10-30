select i.id, i.organisation_id, i.total
from invoices i
where i.total >= 100

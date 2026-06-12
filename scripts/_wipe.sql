-- Clean slate before booking-flow redesign (user-requested 2026-06-12):
delete from public.payments;
delete from public.invoices;
delete from public.bookings;
select (select count(*) from public.bookings) as bookings,
       (select count(*) from public.payments) as payments,
       (select count(*) from public.invoices) as invoices;

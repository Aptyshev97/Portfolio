create extension cube

create extension earthdistance

--1. Выведите названия самолётов, которые имеют менее 50 посадочных мест.

select a.model as "Название самолета"
from (
	select aircraft_code, count(seat_no)
	from seats
	group by aircraft_code) t
join aircrafts a on a.aircraft_code = t.aircraft_code 
where count < 50.


--2. Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.

select date_trunc('month', book_date), sum(total_amount)
,round(((sum(total_amount) - 
lag (sum(total_amount)) over (order by date_trunc('month', book_date)))
/(lag (sum(total_amount)) over (order by date_trunc('month', book_date))))*100, 2)
from bookings 
group by 1
order by 1


--3. Выведите названия самолётов без бизнес-класса. Используйте в решении функцию array_agg.

select a.model as "Название самолета без бизнесс-класса"--aircraft_code, array_position(array_agg(distinct fare_conditions), 'Business') 
from seats s
join aircrafts a on a.aircraft_code = s.aircraft_code
group by a.aircraft_code
having array_position(array_agg(distinct s.fare_conditions), 'Business') is null


--4. Выведите накопительный итог количества мест в самолётах по каждому аэропорту на каждый день. 
--Учтите только те самолеты, которые летали пустыми и только те дни, когда из одного аэропорта вылетело более одного такого самолёта.
--Выведите в результат код аэропорта, дату вылета, количество пустых мест и накопительный итог.


	
	with cte1 as(
	select flight_id --16773 
	from flights
	where actual_departure is not null
	except 
	select flight_id  --11518
	from boarding_passes
	group by 1),                                                                                   
cte2 as (
	select aircraft_code, count(seat_no) as "Seats"
	from seats
	group by aircraft_code)
select t1.departure_airport, t1.actual_departure::date, "Seats", sum("Seats") over (partition by t1.departure_airport, date_trunc('day',  t1.actual_departure)  order by  t1.actual_departure)
from (
	select *
	from (
		select cte1.flight_id, f.flight_id, f.departure_airport, f. aircraft_code, 
		f.actual_departure, count (f.flight_id) over (partition by f.departure_airport, f.actual_departure::date)
		from cte1
		join flights f on f.flight_id =cte1.flight_id) t
	join aircrafts a on a.aircraft_code= t.aircraft_code
	join cte2 on cte2.aircraft_code =a.aircraft_code 
	where t.count > 1) t1

--5. Найдите процентное соотношение перелётов по маршрутам от общего количества перелётов. 
--Выведите в результат названия аэропортов и процентное отношение.


select distinct (count(f.flight_id) over (partition by a.airport_code, a2.airport_code))/(sum(count (f.flight_id)) over (partition by  count(f.flight_id)))*100 as "Отношение", 
concat (a.airport_name,  '-', a2.airport_name) "Название аэропортов"
from flights f
join airports a on a.airport_code = f.departure_airport
join airports a2 on a2.airport_code = f.arrival_airport
group by f.flight_id, a.airport_code, a2.airport_code



--6. Выведите количество пассажиров по каждому коду сотового оператора. Код оператора – это три символа после +7
 
select distinct count (passenger_id) "Количество пассажиров", substring(contact_data ->> 'phone', 3, 3) "Код оператора" 
from tickets
group by substring(contact_data ->> 'phone', 3, 3)


--7. Классифицируйте финансовые обороты (сумму стоимости билетов) по маршрутам:
--до 50 млн – low
--от 50 млн включительно до 150 млн – middle
--от 150 млн включительно – high
--Выведите в результат количество маршрутов в каждом полученном классе.

with cte1 as(
	select concat, sum(t.sum)
	from(
		select f.flight_id, sum(tf.amount), 
		concat (f.departure_airport, '-', f.arrival_airport) 
		from flights f
		join ticket_flights tf on tf.flight_id = f.flight_id
		group by f.flight_id) t
	group by concat)
select (select count(concat) "low"
	from cte1 
	where sum < 50000000),
	(select count(concat) "middle"
	from cte1
	where sum >= 50000000 and sum < 150000000),
	(select count(concat) "high"
	from cte1
	where sum >= 150000000)
	

--8. Вычислите медиану стоимости билетов, медиану стоимости бронирования и отношение медианы бронирования к медиане стоимости билетов, результат округлите до сотых. 

select
(select percentile_disc (0.5) within group (order by amount) "Медиана ст-ти билетов"
from ticket_flights),
(select percentile_disc(0.5) within group  (order by total_amount) "Медиана ст-ти брони"
from bookings), round((select percentile_disc(0.5) within group  (order by total_amount) 
from bookings) / (select percentile_disc (0.5) within group (order by amount)
from ticket_flights),2) "Отношение"


--9. Найдите значение минимальной стоимости одного километра полёта для пассажира. Для этого определите расстояние между аэропортами и учтите стоимость билетов.
--Для поиска расстояния между двумя точками на поверхности Земли используйте дополнительный модуль earthdistance. 
--Для работы данного модуля нужно установить ещё один модуль – cube.
--Важно: 
--Установка дополнительных модулей происходит через оператор CREATE EXTENSION название_модуля.
--В облачной базе данных модули уже установлены.
--Функция earth_distance возвращает результат в метрах.


select min (summ)
from (
	select f.flight_id,-- concat(f.departure_airport, '-', f.arrival_airport),
	earth_distance(ll_to_earth(a.latitude, a.longitude),ll_to_earth(a2.latitude, a2.longitude))/1000 as dist, tf.amount,
	tf.amount /(earth_distance(ll_to_earth(a.latitude, a.longitude),ll_to_earth(a2.latitude, a2.longitude))/1000) as summ
	from flights f
	join airports a on a.airport_code = f.departure_airport
	join airports a2 on a2.airport_code =f.arrival_airport
	join ticket_flights tf on tf.flight_id = f.flight_id) t





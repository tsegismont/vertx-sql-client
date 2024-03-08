ALTER SESSION SET CONTAINER=FREEPDB1;

CREATE TABLE World
(
  id           INTEGER           NOT NULL,
  randomNumber INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (id)
);

INSERT INTO World (id, randomNumber)
SELECT Rownum r, dbms_random.value
FROM dual
CONNECT BY Rownum <= 100;

-- Fortune Table
CREATE TABLE Fortune
(
    id      integer GENERATED by default on null as IDENTITY,
    message varchar(2048),
    PRIMARY KEY (id)
);
INSERT INTO Fortune (message)
VALUES ('fortune: No such file or directory');
INSERT INTO Fortune (message)
VALUES ('A computer scientist is someone who fixes things that are not broken.');
INSERT INTO Fortune (message)
VALUES ('After enough decimal places, nobody gives a damn.');
INSERT INTO Fortune (message)
VALUES ('A bad random number generator: 1, 1, 1, 1, 1, 4.33e+67, 1, 1, 1');
INSERT INTO Fortune (message)
VALUES ('A computer program does what you tell it to do, not what you want it to do.');
INSERT INTO Fortune (message)
VALUES ('Emacs is a nice operating system, but I prefer UNIX. — Tom Christaensen');
INSERT INTO Fortune (message)
VALUES ('Any program that runs right is obsolete.');
INSERT INTO Fortune (message)
VALUES ('A list is only as strong as its weakest link. — Donald Knuth');
INSERT INTO Fortune (message)
VALUES ('Feature: A bug with seniority.');
INSERT INTO Fortune (message)
VALUES ('Computers make very fast, very accurate mistakes.');
INSERT INTO Fortune (message)
VALUES ('<script>alert("This should not be displayed in a browser alert box.");</script>');
INSERT INTO Fortune (message)
VALUES ('フレームワークのベンチマーク');

-- immutable table for select query testing --
-- used by TCK

CREATE TABLE immutable
(
    id      integer       NOT NULL,
    message varchar(2048) NOT NULL,
    PRIMARY KEY (id)
);
INSERT INTO immutable (id, message)
VALUES (1, 'fortune: No such file or directory');
INSERT INTO immutable (id, message)
VALUES (2, 'A computer scientist is someone who fixes things that aren''t broken.');
INSERT INTO immutable (id, message)
VALUES (3, 'After enough decimal places, nobody gives a damn.');
INSERT INTO immutable (id, message)
VALUES (4, 'A bad random number generator: 1, 1, 1, 1, 1, 4.33e+67, 1, 1, 1');
INSERT INTO immutable (id, message)
VALUES (5, 'A computer program does what you tell it to do, not what you want it to do.');
INSERT INTO immutable (id, message)
VALUES (6, 'Emacs is a nice operating system, but I prefer UNIX. — Tom Christaensen');
INSERT INTO immutable (id, message)
VALUES (7, 'Any program that runs right is obsolete.');
INSERT INTO immutable (id, message)
VALUES (8, 'A list is only as strong as its weakest link. — Donald Knuth');
INSERT INTO immutable (id, message)
VALUES (9, 'Feature: A bug with seniority.');
INSERT INTO immutable (id, message)
VALUES (10, 'Computers make very fast, very accurate mistakes.');
INSERT INTO immutable (id, message)
VALUES (11, '<script>alert("This should not be displayed in a browser alert box.");</script>');
INSERT INTO immutable (id, message)
VALUES (12, 'フレームワークのベンチマーク');

-- mutable for insert,update,delete query testing --
-- used by TCK
CREATE TABLE mutable
(
    id  integer       NOT NULL,
    val varchar(2048) NOT NULL,
    PRIMARY KEY (id)
);

-- Collector API testing
CREATE TABLE test_collector
(
  id           INT,
  test_int_2   SMALLINT,
  test_int_4   INT,
  test_int_8   CLOB,
  test_float   FLOAT,
  test_double  NUMBER,
  test_varchar VARCHAR(20)
);

INSERT INTO test_collector
VALUES (1, 32767, 2147483647, 9223372036854775807, 123.456, 1.234567, 'HELLO,WORLD');
INSERT INTO test_collector
VALUES (2, 32767, 2147483647, 9223372036854775807, 123.456, 1.234567, 'hello,world');

CREATE TABLE basicdatatype
(
  id           INT,
  test_int_2   SMALLINT,
  test_int_4   INT,
  test_int_8   NUMBER(19),
  test_float_4 FLOAT(23),
  test_numeric NUMBER(5, 2),
  test_decimal DECIMAL,
  test_char    CHAR(8),
  test_varchar VARCHAR(20),
  test_date    DATE
);
INSERT INTO basicdatatype(id, test_int_2, test_int_4, test_int_8, test_float_4, test_numeric,
                          test_decimal, test_char, test_varchar, test_date)
VALUES (1, 32767, 2147483647, 9223372036854775807, 3.40282E38, 999.99,
        12345, 'testchar', 'testvarchar', TO_DATE('2019-01-01', 'YYYY-MM-DD'));
INSERT INTO basicdatatype(id, test_int_2, test_int_4, test_int_8, test_float_4, test_numeric,
                          test_decimal, test_char, test_varchar, test_date)
VALUES ('2', '32767', '2147483647', '9223372036854775807', '3.40282E38', '999.99',
        '12345', 'testchar', 'testvarchar', TO_DATE('2019-01-01', 'YYYY-MM-DD'));
INSERT INTO basicdatatype(id, test_int_2, test_int_4, test_int_8, test_float_4, test_numeric,
                          test_decimal, test_char, test_varchar, test_date)
VALUES (3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

CREATE TABLE binary_data_types
(
  id        INT,
  test_raw  RAW(255),
  test_blob BLOB
);
INSERT INTO binary_data_types(id, test_raw, test_blob)
VALUES (1, UTL_RAW.CAST_TO_RAW('See you space cowboy...'), UTL_RAW.CAST_TO_RAW('See you space cowboy...'));
INSERT INTO binary_data_types(id, test_raw, test_blob)
VALUES (2, UTL_RAW.CAST_TO_RAW('See you space cowboy...'), UTL_RAW.CAST_TO_RAW('See you space cowboy...'));
INSERT INTO binary_data_types(id, test_raw, test_blob)
VALUES (3, NULL, NULL);

CREATE TABLE temporal_data_types
(
  id                           INT,
  test_date                    DATE,
  test_timestamp               TIMESTAMP,
  test_timestamp_with_timezone TIMESTAMP WITH TIME ZONE
);
INSERT INTO temporal_data_types(id, test_date, test_timestamp, test_timestamp_with_timezone)
VALUES (1, date '2019-11-04', timestamp '2018-11-04 15:13:28', timestamp '2019-11-04 15:13:28 +01:02');
INSERT INTO temporal_data_types(id, test_date, test_timestamp, test_timestamp_with_timezone)
VALUES (2, date '2019-11-04', timestamp '2018-11-04 15:13:28', timestamp '2019-11-04 15:13:28 +01:02');
INSERT INTO temporal_data_types(id, test_date, test_timestamp, test_timestamp_with_timezone)
VALUES (3, NULL, NULL, NULL);

-- No response reproducer

CREATE TABLE passenger
(
  id             NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  nif            VARCHAR(15) NOT NULL,
  name           VARCHAR(25) NOT NULL,
  last_name      VARCHAR(55) NOT NULL,
  contact_number VARCHAR(20) NOT NULL,
  created_at     INT         NOT NULL,
  updated_at     INT,
  address_id     NUMBER
);


-- These are the sql commands executed by ORM to facilitate support for String[] array type
CREATE OR REPLACE TYPE StringArrayType  AS VARYING array(127) of varchar2(255 char);

CREATE TABLE StringsArrayTable
(
  id number(10,0),
  stringarrayelement StringArrayType,
  primary key (id)
);

-- The following is ORM-generated DDL to manage various array use situations in embedded and type conversion situations and may or may not be relevant at the moment
--create or replace function StringArrayType_cmp(a in StringArrayType, b in StringArrayType) return number deterministic is begin if a is null or b is null then return null; end if; for i in 1 .. least(a.count,b.count) loop if a(i) is null or b(i) is null then return null;elsif a(i)>b(i) then return 1;elsif a(i)<b(i) then return -1; end if; end loop; if a.count=b.count then return 0; elsif a.count>b.count then return 1; else return -1; end if; end;
--create or replace function StringArrayType_distinct(a in StringArrayType, b in StringArrayType) return number deterministic is begin if a is null and b is null then return 0; end if; if a is null or b is null or a.count <> b.count then return 1; end if; for i in 1 .. a.count loop if (a(i) is null)<>(b(i) is null) or a(i)<>b(i) then return 1; end if; end loop; return 0; end;
--create or replace function StringArrayType_position(arr in StringArrayType, elem in varchar2, startPos in number default 1) return number deterministic is begin if arr is null then return null; end if; if elem is null then for i in startPos .. arr.count loop if arr(i) is null then return i; end if; end loop; else for i in startPos .. arr.count loop if arr(i)=elem then return i; end if; end loop; end if; return 0; end;
--create or replace function StringArrayType_length(arr in StringArrayType) return number deterministic is begin if arr is null then return null; end if; return arr.count; end;
--create or replace function StringArrayType_concat(arr0 in StringArrayType,arr1 in StringArrayType,arr2 in StringArrayType default StringArrayType(),arr3 in StringArrayType default StringArrayType(),arr4 in StringArrayType default StringArrayType()) return StringArrayType deterministic is res StringArrayType; begin if arr0 is null or arr1 is null or arr2 is null or arr3 is null or arr4 is null then return null; end if; select * bulk collect into res from (select * from table(arr0) union all select * from table(arr1) union all select * from table(arr2) union all select * from table(arr3) union all select * from table(arr4)); return res; end;
--create or replace function StringArrayType_contains(haystack in StringArrayType, needle in StringArrayType, nullable in number) return number deterministic is found number(1,0); begin if haystack is null or needle is null then return null; end if; for i in 1 .. needle.count loop found := 0; for j in 1 .. haystack.count loop if nullable = 1 and needle(i) is null and haystack(j) is null or needle(i)=haystack(j) then found := 1; exit; end if; end loop; if found = 0 then return 0; end if;end loop; return 1; end;
--create or replace function StringArrayType_overlaps(haystack in StringArrayType, needle in StringArrayType, nullable in number) return number deterministic is begin if haystack is null or needle is null then return null; end if; if needle.count = 0 then return 1; end if; for i in 1 .. needle.count loop for j in 1 .. haystack.count loop if nullable = 1 and needle(i) is null and haystack(j) is null or needle(i)=haystack(j) then return 1; end if; end loop; end loop; return 0; end;
--create or replace function StringArrayType_get(arr in StringArrayType, idx in number) return varchar2 deterministic is begin if arr is null or idx is null or arr.count < idx then return null; end if; return arr(idx); end;
--create or replace function StringArrayType_set(arr in StringArrayType, idx in number, elem in varchar2) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is not null then for i in 1 .. arr.count loop res.extend; res(i) := arr(i); end loop; for i in arr.count+1 .. idx loop res.extend; end loop; else for i in 1 .. idx loop res.extend; end loop; end if; res(idx) := elem; return res; end;
--create or replace function StringArrayType_remove(arr in StringArrayType, elem in varchar2) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is null then return null; end if; if elem is null then for i in 1 .. arr.count loop if arr(i) is not null then res.extend; res(res.last) := arr(i); end if; end loop; else for i in 1 .. arr.count loop if arr(i) is null or arr(i)<>elem then res.extend; res(res.last) := arr(i); end if; end loop; end if; return res; end;
--create or replace function StringArrayType_remove_index(arr in StringArrayType, idx in number) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is null or idx is null then return arr; end if; for i in 1 .. arr.count loop if i<>idx then res.extend; res(res.last) := arr(i); end if; end loop; return res; end;
--create or replace function StringArrayType_slice(arr in StringArrayType, startIdx in number, endIdx in number) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is null or startIdx is null or endIdx is null then return null; end if; for i in startIdx .. least(arr.count,endIdx) loop res.extend; res(res.last) := arr(i); end loop; return res; end;
--create or replace function StringArrayType_replace(arr in StringArrayType, old in varchar2, elem in varchar2) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is null then return null; end if; if old is null then for i in 1 .. arr.count loop res.extend; res(res.last) := coalesce(arr(i),elem); end loop; else for i in 1 .. arr.count loop res.extend; if arr(i) = old then res(res.last) := elem; else res(res.last) := arr(i); end if; end loop; end if; return res; end;
--create or replace function StringArrayType_trim(arr in StringArrayType, elems number) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if arr is null or elems is null then return null; end if; if arr.count < elems then raise_application_error (-20000, 'number of elements to trim must be between 0 and '||arr.count); end if;for i in 1 .. arr.count-elems loop res.extend; res(i) := arr(i); end loop; return res; end;
--create or replace function StringArrayType_fill(elem in varchar2, elems number) return StringArrayType deterministic is res StringArrayType:=StringArrayType(); begin if elems is null then return null; end if; if elems<0 then raise_application_error (-20000, 'number of elements must be greater than or equal to 0'); end if;for i in 1 .. elems loop res.extend; res(i) := elem; end loop; return res; end;
--create or replace function StringArrayType_positions(arr in StringArrayType, elem in varchar2) return sdo_ordinate_array deterministic is res sdo_ordinate_array:=sdo_ordinate_array(); begin if arr is null then return null; end if; if elem is null then for i in 1 .. arr.count loop if arr(i) is null then res.extend; res(res.last):=i; end if; end loop; else for i in 1 .. arr.count loop if arr(i)=elem then res.extend; res(res.last):=i; end if; end loop; end if; return res; end;
--create or replace function StringArrayType_to_string(arr in StringArrayType, sep in varchar2) return varchar2 deterministic is res varchar2(4000):=''; begin if arr is null or sep is null then return null; end if; for i in 1 .. arr.count loop if arr(i) is not null then if length(res)<>0 then res:=res||sep; end if; res:=res||arr(i); end if; end loop; return res; end;


-- Don't forget to commit...
COMMIT;

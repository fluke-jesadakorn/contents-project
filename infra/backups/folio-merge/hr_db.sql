--
-- PostgreSQL database dump
--

\restrict JfvwB6AkWwYlSk3GusVtEI4mfKNg1sUqYa7wfpoDDIe6bvSuA253uwcLB4vb2aY

-- Dumped from database version 18.4 (Homebrew)
-- Dumped by pg_dump version 18.4 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    employee_code text NOT NULL,
    line_user_id text,
    name text NOT NULL,
    department text NOT NULL,
    "position" text NOT NULL,
    role text DEFAULT 'staff'::text NOT NULL,
    job_description text NOT NULL,
    total_sick_leave integer DEFAULT 30,
    used_sick_leave integer DEFAULT 0,
    total_annual_leave integer DEFAULT 10,
    used_annual_leave integer DEFAULT 0,
    total_personal_leave integer DEFAULT 6,
    used_personal_leave integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    leave_type text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    days numeric(3,1) NOT NULL,
    reason text,
    status text DEFAULT 'pending'::text NOT NULL,
    approved_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    reject_reason text
);


--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_sessions (
    line_user_id text NOT NULL,
    current_state text DEFAULT 'idle'::text NOT NULL,
    temp_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.employees (id, employee_code, line_user_id, name, department, "position", role, job_description, total_sick_leave, used_sick_leave, total_annual_leave, used_annual_leave, total_personal_leave, used_personal_leave, created_at, updated_at) FROM stdin;
c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	EMP003	\N	สมรักษ์ พารวย	HR	HR Specialist	hr	ดูแลสวัสดิการของพนักงาน วางแผนกิจกรรม สรรหาบุคลากร และอนุมัติใบลาภาพรวมของบริษัท	30	0	15	2	6	0	2026-06-24 10:59:48.097126+07	2026-06-24 10:59:48.097126+07
d4e5f67a-8b9c-0d1e-2f3a-4b5c6d7e8f9a	EMP004	\N	สมพงษ์ คล่องแคล่ว	HR	HR Assistant	staff	ช่วยประสานงานเอกสารภายในทีม HR บันทึกประวัติพนักงาน และดูแลการประสานสิทธิ์ต่างๆ	30	0	10	0	6	0	2026-06-24 10:59:48.097126+07	2026-06-24 10:59:48.097126+07
e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	EMP005	\N	วิภา พรประเสริฐ	HR	HR Director	hr	กำกับดูแลนโยบายบริหารงานบุคคล พัฒนาองค์กร พิจารณาอนุมัติวันลาในระดับผู้บริหารสูงสุด	30	0	20	0	6	0	2026-06-24 10:59:48.097126+07	2026-06-24 10:59:48.097126+07
a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	EMP001	\N	สมชาย ดีใจ	Engineering	Senior Developer	staff	พัฒนาและดูแลระบบเว็บแอปพลิเคชัน เขียน unit test และทำ code review ร่วมกับทีมร่วมงาน	30	3	10	12	6	1	2026-06-24 10:59:48.097126+07	2026-06-24 13:54:26.83093+07
b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	EMP002	Ueb33f1b55f1235886ed016073775c7a4	สมศรี รักงาน	Engineering	Engineering Manager	manager	บริหารทีมวิศวกร วางแผนการทำงาน ตรวจสอบคุณภาพงาน และพิจารณาอนุมัติคำขอลาหยุดของคนในทีม	0	0	10	0	5	0	2026-06-24 10:59:48.097126+07	2026-06-25 00:14:01.595831+07
\.


--
-- Data for Name: leave_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.leave_requests (id, employee_id, leave_type, start_date, end_date, days, reason, status, approved_by, created_at, updated_at, reject_reason) FROM stdin;
53319346-9cdc-49e4-b5ba-d9a3093fce0d	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	annual	2026-06-12	2026-06-13	2.0	ทำธุระส่วนตัวเรื่องบ้านใหม่	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-14 10:59:48.098533+07	2026-06-24 10:59:48.098533+07	\N
06313614-d7c9-4447-a33c-2b9a896b5162	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-10	2026-06-10	1.0	พบแพทย์รักษาฟันคุด	approved	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-12 10:59:48.098533+07	2026-06-24 10:59:48.098533+07	\N
07f2ca08-20a8-4ce4-bbcb-668b1c301b04	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-24	2026-06-24	1.0	ป่วยเป็นไข้น้ำร้อนลวก	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 12:56:27.765195+07	2026-06-24 13:01:19.480521+07	\N
cb440cec-a3db-49c0-b2a7-4253e0746cb3	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-24	2026-06-24	1.0	ท้องเสียไม่หยุดตั้งแต่กลางคืน	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 12:50:33.597463+07	2026-06-24 13:03:46.514638+07	\N
61ac9ab6-7bde-445b-b3d9-8f352330ef83	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	personal	2026-06-25	2026-06-27	3.0	ไปทำใบขับขี่	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 12:50:37.470336+07	2026-06-24 13:03:53.703677+07	ข้อมูลวันลากิจไม่สอดคล้องกับระเบียบ
adf32288-3f82-4520-a122-5289219160b1	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-24	2026-06-24	1.0	เป็นไข้น้ำร้อนลวก	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 13:09:46.642464+07	2026-06-24 13:10:13.759212+07	ป่วยปลอม
f823cb1c-8862-410a-9963-2632ef513e4a	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	personal	2026-06-23	2026-06-23	1.0	ไปเที่ยวจนป่วย	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 13:11:22.897496+07	2026-06-24 13:11:34.065637+07	\N
1da57695-6a94-4fa4-b620-6eb78c379b1a	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-23	2026-06-23	1.0	ลาไปเที่ยว	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 13:29:16.386802+07	2026-06-24 13:29:36.713733+07	เที่ยวมันจะไปป่วยได้ไง
e2fa3c77-7492-4de8-9c4f-502c0736e767	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	sick	2026-06-24	2026-06-25	2.0	เป็นไข้หวัดตัวร้อน	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 12:22:17.565099+07	2026-06-24 13:54:12.912948+07	ไม่ชอบ
43abb4d5-18fb-44e9-9834-6248928c8e61	d4e5f67a-8b9c-0d1e-2f3a-4b5c6d7e8f9a	sick	2026-06-24	2026-06-24	1.0	เป็นไข้หวัดใหญ่ ปวดศีรษะสูง	rejected	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 10:29:48.098533+07	2026-06-24 13:54:25.368146+07	ไม่รู้มั่ว
c9b06063-bd1e-4707-9022-1929bf455354	a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d	annual	2026-06-25	2026-06-26	2.0	พักผ่อนกับครอบครัวต่างจังหวัด	approved	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 09:59:48.098533+07	2026-06-24 13:54:26.83093+07	\N
0d5bda03-4907-4d1f-a92c-279a38a68bb8	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	annual	2026-06-25	2026-06-25	1.0	ลากลับบ้าน	rejected	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 17:53:12.412987+07	2026-06-24 17:55:46.865453+07	ผิดวัน
bd79ca7e-76d1-44a9-a637-4ce1166d83eb	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-24	2026-06-24	1.0	มีอาการท้องเสีย	rejected	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 22:16:29.51126+07	2026-06-24 22:19:13.790625+07	ตอแหล
84754a16-776d-447b-8210-2b9c89598cac	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-24	2026-06-24	1.0	เป็นไข้	approved	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 17:52:24.774081+07	2026-06-24 22:19:45.789203+07	\N
9889e7c1-60da-4dd4-8fef-d64530b1f2b0	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-25	2026-06-25	1.0	ไปเที่ยว	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 23:47:20.741646+07	2026-06-24 23:50:12.206567+07	กดผิด
4c8dc0bf-8247-4ad2-8213-2ef6b2d88f60	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-26	2026-06-26	1.0	ปวดศีรษะตัวร้อน	rejected	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-24 23:53:51.431843+07	2026-06-24 23:53:55.695622+07	ไม่อนุมัติเนื่องจากพนักงานมีงานด่วน
24a745be-2f92-4ccb-b39c-725ae96975e9	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-24	2026-06-24	1.0	เนื่องจากมีไข้	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 23:55:34.859395+07	2026-06-24 23:55:45.411135+07	\N
014017b2-09a1-4d8c-9470-e2f8a93f8cb8	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	personal	2026-06-25	2026-06-25	1.0	เนื่องจากทำใบขับขี่	rejected	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-24 23:56:09.153037+07	2026-06-24 23:56:24.935891+07	พรุ่งนี้ประชุมรวม
7d9d00eb-46af-4842-949c-3b7c7add553c	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-25	2026-06-25	1.0	เนื่องจากเป็นไข้เลือดออก	rejected	c3d4e5f6-7a8b-9c0d-1e2f-3a4b5c6d7e8f	2026-06-25 00:11:27.56915+07	2026-06-25 00:12:28.970015+07	เหตุผลไม่เพียงพอ
53b48eed-3697-43e7-9115-76a63bfd0447	b2c3d4e5-f67a-8b9c-0d1e-2f3a4b5c6d7e	sick	2026-06-25	2026-06-25	1.0	เนื่องจากรถชนขาขาด	approved	e5f67a8b-9c0d-1e2f-3a4b-5c6d7e8f9a0b	2026-06-25 00:13:00.201365+07	2026-06-25 00:13:26.608735+07	\N
\.


--
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_sessions (line_user_id, current_state, temp_data, updated_at) FROM stdin;
U_TEST_USER_123	idle	{}	2026-06-24 11:06:13.083145+07
Utestuser123456	idle	{}	2026-06-24 12:49:21.104729+07
Ueb33f1b55f1235886ed016073775c7a4	idle	{}	2026-06-24 11:49:04.891712+07
\.


--
-- Name: employees employees_employee_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_code_key UNIQUE (employee_code);


--
-- Name: employees employees_line_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_line_user_id_key UNIQUE (line_user_id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (line_user_id);


--
-- Name: idx_employees_line_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_line_user ON public.employees USING btree (line_user_id);


--
-- Name: idx_leave_requests_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_employee ON public.leave_requests USING btree (employee_id);


--
-- Name: idx_leave_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_status ON public.leave_requests USING btree (status);


--
-- Name: idx_user_sessions_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_sessions_state ON public.user_sessions USING btree (current_state);


--
-- Name: leave_requests leave_requests_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employees(id);


--
-- Name: leave_requests leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict JfvwB6AkWwYlSk3GusVtEI4mfKNg1sUqYa7wfpoDDIe6bvSuA253uwcLB4vb2aY


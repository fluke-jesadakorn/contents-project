-- Seed Roles
INSERT INTO roles (id, name) VALUES
(1, 'staff'),
(2, 'accountant'),
(3, 'manager'),
(4, 'admin')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- Seed Users
INSERT INTO users (employee_code, fullname, role_id, department) VALUES
('EMP001', 'สมชาย ดีใจ', 1, 'Development'),
('EMP002', 'สมศรี รักงาน', 3, 'Engineering'),
('EMP003', 'สมรักษ์ พารวย', 2, 'Finance & Account'),
('EMP004', 'สมพงษ์ คล่องแคล่ว', 1, 'Human Resource'),
('EMP005', 'วิภา พรประเสริฐ', 4, 'Executive')
ON CONFLICT (employee_code) DO NOTHING;

-- Seed Expanded Chart of Accounts (COA)
INSERT INTO chart_of_accounts (code, name, name_th, account_type, embedding) VALUES
-- 1. ASSETS
('110100', 'Cash on Hand', 'เงินสดในมือ', 'asset', NULL),
('110200', 'Cash at Bank - Savings', 'เงินฝากออมทรัพย์', 'asset', NULL),
('110300', 'Cash at Bank - Current', 'เงินฝากกระแสรายวัน', 'asset', NULL),
('110400', 'Accounts Receivable', 'ลูกหนี้การค้า', 'asset', NULL),
('110500', 'Input VAT', 'ภาษีซื้อ', 'asset', NULL),
('110600', 'Prepaid Expenses', 'ค่าใช้จ่ายจ่ายล่วงหน้า', 'asset', NULL),

-- 2. LIABILITIES
('210100', 'Accounts Payable', 'เจ้าหนี้การค้า', 'liability', NULL),
('210200', 'Accrued Expenses', 'ค่าใช้จ่ายค้างจ่าย', 'liability', NULL),
('210300', 'Accrued Output VAT', 'ภาษีขายค้างจ่าย', 'liability', NULL),
('210400', 'Withholding Tax Payable', 'ภาษีหัก ณ ที่จ่ายค้างส่ง', 'liability', NULL),
('210500', 'Employee Reimbursement Payable', 'เจ้าหนี้เงินทดรองจ่ายพนักงาน', 'liability', NULL),

-- 3. EQUITY
('310100', 'Share Capital', 'ทุนเรือนหุ้น', 'equity', NULL),
('310200', 'Retained Earnings', 'กำไรสะสม', 'equity', NULL),

-- 4. REVENUES
('410100', 'Sales Revenue', 'รายได้จากการขาย', 'revenue', NULL),
('410200', 'Service Revenue', 'รายได้จากการบริการ', 'revenue', NULL),
('410300', 'Other Income', 'รายได้อื่น', 'revenue', NULL),

-- 5. EXPENSES
('510100', 'Salaries & Wages', 'เงินเดือนและค่าจ้าง', 'expense', NULL),
('510200', 'Travel & Transportation', 'ค่าพาหนะและค่าเดินทาง', 'expense', NULL),
('510300', 'Office Supplies & Stationery', 'เครื่องเขียนและเครื่องใช้สำนักงาน', 'expense', NULL),
('510400', 'Entertainment & Client Meal', 'ค่ารับรองลูกค้าและอาหาร', 'expense', NULL),
('510500', 'Internet & Utilities', 'ค่าอินเทอร์เน็ตและสาธารณูปโภค', 'expense', NULL),
('510600', 'Post & Delivery', 'ค่าไปรษณีย์และจัดส่ง', 'expense', NULL),
('510700', 'Software & Subscriptions', 'ค่าซอฟต์แวร์และบริการคลาวด์', 'expense', NULL),
('510800', 'Maintenance & Repairs', 'ค่าซ่อมแซมและบำรุงรักษา', 'expense', NULL),
('510900', 'Training & Seminar', 'ค่าฝึกอบรมและสัมมนา', 'expense', NULL),
('520100', 'Office Rental', 'ค่าเช่าสำนักงาน', 'expense', NULL),
('520200', 'Marketing & Advertising', 'ค่าการตลาดและโฆษณา', 'expense', NULL),
('520300', 'Professional & Consulting Fees', 'ค่าธรรมเนียมวิชาชีพและที่ปรึกษา', 'expense', NULL),
('520400', 'Bank Charges', 'ค่าธรรมเนียมธนาคาร', 'expense', NULL),
('520500', 'Insurance Expenses', 'เบี้ยประกันภัย', 'expense', NULL),
('520600', 'Depreciations', 'ค่าเสื่อมราคา', 'expense', NULL),
('520700', 'Taxes & Licenses', 'ค่าภาษีอากรและค่าธรรมเนียม', 'expense', NULL)
ON CONFLICT (code) DO UPDATE SET 
    name = EXCLUDED.name,
    name_th = EXCLUDED.name_th,
    account_type = EXCLUDED.account_type;

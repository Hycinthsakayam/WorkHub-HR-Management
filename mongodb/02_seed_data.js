/* =====================================================================
   WorkHub - MongoDB : sample data
   Run: mongosh "mongodb://localhost:27017" --file mongodb/02_seed_data.js
   Re-runnable: clears the collections first.
   Employee IDs, names, departments and managers match SQL Server WorkHubDB.
   NumberInt() makes the BSON type explicit: the validators require "int",
   and a fractional or computed number would otherwise be stored as a double.
   ===================================================================== */

db = db.getSiblingDB("WorkHubDB");
const I = n => NumberInt(n);
const D = s => new Date(s + "T00:00:00Z");

["employee_profiles", "review_feedback", "hr_notifications"].forEach(c => db.getCollection(c).deleteMany({}));

/* ------------------------------ reference data (same as SQL Server) */
const departments = {
  1:  ["Human Resources", "Ferrovia Corporate HQ", "Mumbai"],
  2:  ["Finance & Payroll", "Ferrovia Corporate HQ", "Mumbai"],
  3:  ["Production - Pune", "Ferrovia Pune Works", "Pune"],
  4:  ["Quality Assurance - Pune", "Ferrovia Pune Works", "Pune"],
  5:  ["Production - Chennai", "Ferrovia Chennai Works", "Chennai"],
  6:  ["Maintenance - Chennai", "Ferrovia Chennai Works", "Chennai"],
  7:  ["Production - Coimbatore", "Ferrovia Coimbatore Works", "Coimbatore"],
  8:  ["Production - Vadodara", "Ferrovia Vadodara Works", "Vadodara"],
  9:  ["Research & Development", "Ferrovia R&D Centre", "Bengaluru"],
  10: ["Supply Chain", "Ferrovia North Warehouse", "Gurugram"],
  11: ["Logistics", "Ferrovia East Logistics Hub", "Kolkata"],
  12: ["Learning & Development", "Ferrovia Training Centre", "Hyderabad"]
};

// [employeeId, first, last, departmentId, managerId]
const employees = [
  [1, "Arjun", "Mehta", 1, null],  [2, "Priya", "Nair", 1, 1],      [3, "Rahul", "Verma", 2, 1],
  [4, "Sneha", "Iyer", 3, 1],      [5, "Karthik", "Raman", 5, 1],   [6, "Ananya", "Desai", 9, 1],
  [7, "Vikram", "Singh", 7, 1],    [8, "Meera", "Pillai", 8, 1],    [9, "Rohan", "Kulkarni", 3, 4],
  [10, "Divya", "Menon", 4, 4],    [11, "Aditya", "Joshi", 3, 4],   [12, "Lakshmi", "Subramanian", 5, 5],
  [13, "Suresh", "Babu", 6, 5],    [14, "Fatima", "Sheikh", 5, 5],  [15, "Nikhil", "Patil", 9, 6],
  [16, "Kavya", "Reddy", 9, 6],    [17, "Ganesh", "Murugan", 7, 7], [18, "Pooja", "Shah", 8, 8],
  [19, "Imran", "Khan", 8, 8],     [20, "Neha", "Gupta", 1, 2],     [21, "Siddharth", "Rao", 2, 3],
  [22, "Ritu", "Agarwal", 2, 3],   [23, "Manoj", "Tiwari", 10, 1],  [24, "Deepa", "Krishnan", 10, 23],
  [25, "Arvind", "Chauhan", 11, 23], [26, "Swati", "Bhatt", 12, 2], [27, "Harish", "Kumar", 6, 5],
  [28, "Ishita", "Banerjee", 4, 4], [29, "Tarun", "Malhotra", 7, 7], [30, "Zoya", "Fernandes", 9, 6]
];
const managerIds = new Set(employees.map(e => e[4]).filter(m => m !== null));

// Skill pools per department; each employee gets 3 skills with a deterministic level.
const skillPool = {
  1: ["Recruitment", "Employee Relations", "HR Analytics", "Labour Law"],
  2: ["Payroll Processing", "Financial Reporting", "Excel", "Taxation"],
  3: ["CNC Machining", "Lean Manufacturing", "Shift Planning", "Safety Compliance"],
  4: ["ISO 9001", "Six Sigma", "Root Cause Analysis", "Metrology"],
  5: ["CNC Machining", "Lean Manufacturing", "Welding", "Safety Compliance"],
  6: ["Preventive Maintenance", "PLC Programming", "Hydraulics", "Safety Compliance"],
  7: ["Lean Manufacturing", "Assembly Line Ops", "Shift Planning", "Safety Compliance"],
  8: ["Welding", "Lean Manufacturing", "Assembly Line Ops", "Safety Compliance"],
  9: ["CAD Design", "Materials Science", "Simulation", "Python"],
  10: ["Inventory Planning", "Vendor Management", "SAP MM", "Excel"],
  11: ["Fleet Management", "Route Planning", "Forklift Operation", "SAP MM"],
  12: ["Instructional Design", "Public Speaking", "LMS Administration", "Excel"]
};
const certPool = {
  4: ["ISO 9001 Lead Auditor", "Six Sigma Green Belt"], 6: ["Electrical Safety Level 2"],
  9: ["Certified SolidWorks Professional"], 11: ["Forklift Operator Licence"],
  2: ["Certified Payroll Professional"], 3: ["Lean Practitioner"], 5: ["Welding Inspector"]
};
const languages = [["English", "Hindi"], ["English", "Tamil"], ["English", "Marathi"], ["English", "Hindi", "Gujarati"], ["English", "Kannada"]];

/* ------------------------------ 1. employee_profiles (30 docs) */
const profiles = employees.map(([id, first, last, dept, mgr]) => {
  const [dName, plant, city] = departments[dept];
  const pool = skillPool[dept];
  const skills = [0, 1, 2].map(k => ({ name: pool[(id + k) % pool.length], level: I(((id * 3 + k * 2) % 5) + 1) }));
  const certs = (certPool[dept] || []).slice(0, (id % 2) + 1).map((c, k) => ({
    name: c,
    issuedOn: D(`20${22 + (id % 3)}-0${(k % 8) + 1}-15`),
    expiresOn: id % 4 === 0 ? D(`2027-0${(id % 2) + 1}-10`) : D(`2028-0${(k % 8) + 1}-15`)
  }));
  return {
    employeeId: I(id),
    name: { first, last },
    email: `${first.toLowerCase()}.${last.toLowerCase()}@ferrovia.com`,
    role: managerIds.has(id) ? "Manager" : "Employee",
    department: { id: I(dept), name: dName, plant, city },
    skills,
    certifications: certs,
    languages: languages[id % languages.length],
    emergencyContact: { name: `Contact of ${first}`, relation: id % 2 ? "Spouse" : "Parent", phone: `+91 98${String(10000000 + id * 7919).slice(0, 8)}` },
    updatedAt: D("2026-11-01")
  };
});
db.employee_profiles.insertMany(profiles);

/* ------------------------------ 2. review_feedback (manager + peer feedback) */
const strengthsPool = ["Ownership", "Technical depth", "Teamwork", "Safety mindset", "Problem solving", "Communication", "Mentoring", "Reliability"];
const improvePool = ["Delegation", "Documentation", "Time management", "Presenting to leadership", "Cross-team collaboration"];
const feedback = [];
employees.forEach(([id, , , dept, mgr]) => {
  [2025, 2026].forEach(cycle => {
    if (cycle === 2026 && id % 3 === 0) return;              // 2026 cycle still in progress
    const givers = [];
    if (mgr !== null) givers.push([mgr, "Manager"]);
    const peer = employees.find(e => e[3] === dept && e[0] !== id && e[0] !== mgr);
    if (peer) givers.push([peer[0], "Peer"]);
    givers.forEach(([giver, rel], g) => {
      const rating = ((id * 7 + cycle + g * 3) % 5) + 1;
      feedback.push({
        employeeId: I(id), cycle: I(cycle),
        givenBy: { employeeId: I(giver), relationship: rel },
        rating: I(rating < 2 && id % 4 !== 0 ? rating + 2 : rating),
        strengths: [strengthsPool[(id + g) % 8], strengthsPool[(id + cycle) % 8]].filter((v, i, a) => a.indexOf(v) === i),
        improvements: [improvePool[(id + g + cycle) % 5]],
        comments: `${rel} feedback for cycle ${cycle}.`,
        submittedAt: D(`${cycle}-1${(id % 2) + 0}-1${g + 1}`)
      });
    });
  });
});
db.review_feedback.insertMany(feedback);

/* ------------------------------ 3. hr_notifications */
// Review reminders for the 16 employees without a 2026 review in SQL Server
const notReviewed2026 = [1, 3, 5, 7, 8, 11, 13, 14, 17, 19, 22, 23, 25, 27, 28, 29];
const notes = notReviewed2026.map((id, k) => {
  const e = employees.find(x => x[0] === id);
  return {
    type: "REVIEW_REMINDER", recipientId: I(e[4] ?? 2), subjectEmployeeId: I(id),
    message: `Reminder: ${e[1]} ${e[2]} (#${id}) has no 2026 performance review.`,
    channel: "Email", status: k % 3 === 0 ? "Read" : (k % 3 === 1 ? "Sent" : "Queued"),
    createdAt: D("2026-11-20"), readAt: k % 3 === 0 ? D("2026-11-21") : null
  };
});
notes.push(
  { type: "LEAVE_APPROVED", recipientId: I(12), subjectEmployeeId: I(12), message: "Your Annual leave 16-20 Nov 2026 was approved.", channel: "InApp", status: "Read", createdAt: D("2026-11-10"), readAt: D("2026-11-10") },
  { type: "LEAVE_APPROVED", recipientId: I(18), subjectEmployeeId: I(18), message: "Your Sick leave 19-20 Nov 2026 was approved.", channel: "SMS", status: "Sent", createdAt: D("2026-11-19"), readAt: null },
  { type: "LEAVE_REJECTED", recipientId: I(11), subjectEmployeeId: I(11), message: "Your Annual leave 10-14 Aug 2026 was rejected.", channel: "Email", status: "Read", createdAt: D("2026-08-01"), readAt: D("2026-08-02") },
  { type: "PAYROLL_READY", recipientId: I(3), subjectEmployeeId: null, message: "Payroll inputs for 2026-10 are ready: 30 employees, net INR 2,161,820.93.", channel: "Email", status: "Read", createdAt: D("2026-11-01"), readAt: D("2026-11-02") },
  { type: "WAITLIST_PROMOTED", recipientId: I(14), subjectEmployeeId: I(14), message: "A seat opened: you are now enrolled in Lean Manufacturing Basics.", channel: "InApp", status: "Queued", createdAt: D("2026-11-22"), readAt: null },
  { type: "CERTIFICATION_EXPIRING", recipientId: I(28), subjectEmployeeId: I(28), message: "Your ISO 9001 Lead Auditor certification expires on 2027-01-10.", channel: "Email", status: "Sent", createdAt: D("2026-11-15"), readAt: null }
);
db.hr_notifications.insertMany(notes);

print("Seeded WorkHubDB (MongoDB):");
["employee_profiles", "review_feedback", "hr_notifications"].forEach(c =>
  print(`  ${c.padEnd(20)} ${db.getCollection(c).countDocuments()} documents`));

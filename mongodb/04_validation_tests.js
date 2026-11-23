/* =====================================================================
   WorkHub - MongoDB : prove the $jsonSchema validators
   Run: mongosh "mongodb://localhost:27017" --file mongodb/04_validation_tests.js
   Each invalid insert must be REJECTED (error code 121 = DocumentValidationFailure,
   11000 = duplicate key). Valid inserts are deleted again, so data is unchanged.
   ===================================================================== */

db = db.getSiblingDB("WorkHubDB");
const I = n => NumberInt(n);
let passed = 0, failed = 0;

function expect(label, shouldPass, action) {
  let ok, detail;
  try {
    const res = action();
    ok = shouldPass;
    detail = "accepted";
    if (res && res.insertedId) db.getCollection(res.__coll).deleteOne({ _id: res.insertedId });
  } catch (e) {
    ok = !shouldPass;
    detail = `rejected (code ${e.code}${e.code === 121 ? " DocumentValidationFailure" : e.code === 11000 ? " DuplicateKey" : ""})`;
  }
  ok ? passed++ : failed++;
  print(`${ok ? "PASS" : "FAIL"}  ${label.padEnd(48)} ${detail}`);
}
const insert = (coll, doc) => { const r = db.getCollection(coll).insertOne(doc); r.__coll = coll; return r; };

const goodProfile = () => ({
  employeeId: I(999), name: { first: "Test", last: "User" }, email: "test.user@ferrovia.com",
  role: "Employee", department: { id: I(3), name: "Production - Pune" },
  skills: [{ name: "Welding", level: I(3) }], updatedAt: new Date()
});
const goodFeedback = () => ({
  employeeId: I(9), cycle: I(2027), givenBy: { employeeId: I(4), relationship: "Manager" },
  rating: I(4), strengths: ["Ownership"], submittedAt: new Date()
});

print("--- employee_profiles");
expect("valid profile",                         true,  () => insert("employee_profiles", goodProfile()));
expect("missing email",                         false, () => { const d = goodProfile(); delete d.email; return insert("employee_profiles", d); });
expect("invalid email format",                  false, () => insert("employee_profiles", { ...goodProfile(), email: "not-an-email" }));
expect("skill level 9 (must be 1-5)",           false, () => insert("employee_profiles", { ...goodProfile(), skills: [{ name: "Welding", level: I(9) }] }));
expect("employeeId 9.5 (not an integer)",         false, () => insert("employee_profiles", { ...goodProfile(), employeeId: 9.5 }));
expect("unknown field (additionalProperties)",  false, () => insert("employee_profiles", { ...goodProfile(), nickname: "TU" }));
expect("duplicate employeeId (unique index)",   false, () => insert("employee_profiles", { ...goodProfile(), employeeId: I(9), email: "x@ferrovia.com" }));

print("--- review_feedback");
expect("valid feedback",                        true,  () => insert("review_feedback", goodFeedback()));
expect("rating 0",                              false, () => insert("review_feedback", { ...goodFeedback(), rating: I(0) }));
expect("rating 6",                              false, () => insert("review_feedback", { ...goodFeedback(), rating: I(6) }));
expect("relationship 'Boss' (not in enum)",     false, () => insert("review_feedback", { ...goodFeedback(), givenBy: { employeeId: I(4), relationship: "Boss" } }));
expect("same giver twice in one cycle",         false, () => insert("review_feedback", { ...goodFeedback(), cycle: I(2025) }));

print("--- hr_notifications");
expect("valid notification",                    true,  () => insert("hr_notifications", { type: "PAYROLL_READY", recipientId: I(3), message: "Payroll test message", channel: "Email", status: "Queued", createdAt: new Date() }));
expect("unknown type",                          false, () => insert("hr_notifications", { type: "BIRTHDAY", recipientId: I(3), message: "Happy birthday!", channel: "Email", status: "Queued", createdAt: new Date() }));
expect("missing createdAt",                     false, () => insert("hr_notifications", { type: "PAYROLL_READY", recipientId: I(3), message: "Payroll test message", channel: "Email", status: "Queued" }));

print(`\nResult: ${passed} passed, ${failed} failed`);

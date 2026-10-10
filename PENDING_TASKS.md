# Pending Tasks

## Employee employment-status audit trail

Status: Implemented locally; database deployment pending

Implement a reliable audit trail showing who changed an employee's employment status.

Planned work:

- Route every employment-status change through the existing `change_employee_status` database function, including changes made from Employee Dashboard.
- Record the authenticated user automatically in the database rather than trusting a user ID supplied by the frontend.
- Record the employee, previous status, new status, effective date, reason, changer, and actual change timestamp.
- Audit effective-date corrections, including the old date, new date, reason, changer, and timestamp.
- Add a read-only status-history view showing the user's name, transition, effective date, reason, and timestamp.
- Restrict status changes and audit-history access to authorized HR roles.
- Prevent direct employment-status updates that bypass the audit trail.
- Preserve all existing history; display `Unknown/Legacy` when an older record has no recorded user.
- Verify the workflow from Employee Files, Employee Master, and Employee Dashboard before production deployment.

Safety notes:

- Do not alter existing payroll, attendance, or current-status calculations.
- Test the database migration in a transaction or staging environment first.
- Confirm that existing status behavior remains unchanged before deployment.

## Employee shift audit trail

Status: Implemented locally; database deployment pending

Implement a reliable audit trail showing who creates, changes, or deletes an employee's shift without modifying older shift records.

Planned work:

- Add a separate `hr_shift_audit_log` table so existing shift data and version history remain unchanged.
- Capture the authenticated user automatically in the database rather than trusting a user ID supplied by the frontend.
- Use database triggers to cover shift changes from every screen and database path.
- Record the employee, shift type, action (`create`, `update`, or `delete`), old values, new values, and actual change timestamp.
- Cover regular shifts, special weekday shifts, special date-wise shifts, their time slots, and any active legacy or multi-shift tables.
- Preserve deleted shift details in the audit log even when the original shift or slot record is removed.
- Add a read-only shift-history view showing the user, action, previous values, new values, and timestamp.
- Restrict shift changes and audit-history access to authorized HR roles.
- Treat changes made before this feature is deployed as `Unknown/Legacy`; do not attempt to guess who made them.
- Verify create, edit, and delete operations from every active shift-management screen before production deployment.

Safety notes:

- Do not rewrite, delete, or backfill existing shift records.
- Do not change payroll, attendance analysis, or shift-selection behavior.
- Test the database migration in a transaction or staging environment first.
- Confirm that shift creation, editing, and deletion behave exactly as before deployment.

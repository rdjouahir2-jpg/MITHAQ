# Domain layer

Pure TypeScript business rules live here. They must not depend on React, browser storage, or network services. Client-side validation improves UX but is never authoritative; the backend must repeat and enforce all checks transactionally.
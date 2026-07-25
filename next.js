import { Suspense, type ReactNode } from 'react';
import { StaffToolbar } from '../components/staff-toolbar';
 
export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        {children}
        <Suspense fallback={null}>
          <StaffToolbar />
        </Suspense>
      </body>
    </html>
  );
}

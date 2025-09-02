import { db } from '@db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const existingCount = await db.frameworkEditorFramework.count();
    
    if (existingCount > 0) {
      return NextResponse.json({ 
        message: 'Frameworks already exist', 
        count: existingCount 
      });
    }
    
    const frameworks = await db.frameworkEditorFramework.createMany({
      data: [
        {
          name: 'SOC 2 Type II',
          description: 'Service Organization Control 2 Type II certification',
          version: '2017',
          visible: true,
        },
        {
          name: 'ISO 27001',
          description: 'Information security management systems',
          version: '2022',
          visible: true,
        },
        {
          name: 'GDPR',
          description: 'General Data Protection Regulation',
          version: '2016/679',
          visible: true,
        },
        {
          name: 'HIPAA',
          description: 'Health Insurance Portability and Accountability Act',
          version: '1996',
          visible: true,
        },
        {
          name: 'PCI DSS',
          description: 'Payment Card Industry Data Security Standard',
          version: '4.0',
          visible: true,
        }
      ]
    });
    
    return NextResponse.json({ 
      message: 'Frameworks successfully seeded!', 
      count: frameworks.count 
    });
    
  } catch (error) {
    console.error('Error seeding frameworks:', error);
    return NextResponse.json({ 
      error: 'Failed to seed frameworks',
      details: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 });
  }
}

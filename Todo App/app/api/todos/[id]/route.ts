import { NextRequest, NextResponse } from 'next/server';
import dbConnect from '@/lib/mongodb';
import Todo from '@/models/Todo';

// GET a single todo
export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    await dbConnect();
    const todo = await Todo.findById(params.id);
    
    if (!todo) {
      return NextResponse.json(
        { success: false, error: 'Todo not found' },
        { status: 404 }
      );
    }
    
    return NextResponse.json({ success: true, data: todo });
  } catch (error) {
    return NextResponse.json(
      { success: false, error: 'Failed to fetch todo' },
      { status: 500 }
    );
  }
}

// PUT update a todo
export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    await dbConnect();
    const body = await request.json();
    const todo = await Todo.findByIdAndUpdate(params.id, body, {
      new: true,
      runValidators: true,
    });
    
    if (!todo) {
      return NextResponse.json(
        { success: false, error: 'Todo not found' },
        { status: 404 }
      );
    }
    
    return NextResponse.json({ success: true, data: todo });
  } catch (error) {
    return NextResponse.json(
      { success: false, error: 'Failed to update todo' },
      { status: 400 }
    );
  }
}

// DELETE a todo
export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    await dbConnect();
    const todo = await Todo.findByIdAndDelete(params.id);
    
    if (!todo) {
      return NextResponse.json(
        { success: false, error: 'Todo not found' },
        { status: 404 }
      );
    }
    
    return NextResponse.json({ success: true, data: {} });
  } catch (error) {
    return NextResponse.json(
      { success: false, error: 'Failed to delete todo' },
      { status: 500 }
    );
  }
}

import { useId } from 'react';
import { Button } from '../../../components/ui/button';
import { money } from '../../../lib/format/money';
import type { Order } from '../types';
import { OrderRow } from './order-row';

export function OrdersList({ orders }: { orders: Order[] }) {
  const id = useId();
  return <div id={id}><OrderRow /><Button />{money(orders.length)}</div>;
}

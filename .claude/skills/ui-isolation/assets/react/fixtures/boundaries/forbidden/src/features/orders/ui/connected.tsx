import { useOrders } from '../api/orders.queries';
import { useThing } from '../hooks/use-thing';
import { client } from '../../../lib/api/client';
import { useQuery } from '@tanstack/react-query';

export const used = [useOrders, useThing, client, useQuery];

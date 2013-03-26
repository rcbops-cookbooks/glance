#!/usr/bin/env python

import glob
import os
import socket
import sys
import ConfigParser
from kombu import Connection
from kombu import Exchange
from kombu import Queue

REPLICATOR_CONFIG = '/etc/glance/replicator.conf'
GLANCE_API_CONFIG = '/etc/glance/glance-api.conf'


def _read_api_nodes_config():
    config = ConfigParser.RawConfigParser()
    section = 'DEFAULT'

    if config.read(REPLICATOR_CONFIG):
        return config.get(section, 'api_nodes').replace(' ', '').split(',')
    else:
        return None


def _read_glance_api_config():
    glance_cfg = {}
    section = 'DEFAULT'
    config = ConfigParser.RawConfigParser()

    if config.read(GLANCE_API_CONFIG):
        if config.get(section, 'notifier_strategy') == 'rabbit':
            glance_cfg['host'] = config.get(section, 'rabbit_host')
            glance_cfg['port'] = config.get(section, 'rabbit_port')
            glance_cfg['use_ssl'] = config.get(section, 'rabbit_use_ssl')
            glance_cfg['userid'] = config.get(section, 'rabbit_userid')
            glance_cfg['password'] = config.get(section,
                                                'rabbit_password')
            glance_cfg['virtual_host'] = config.get(section,
                                                    'rabbit_virtual_host')
            glance_cfg['exchange'] = config.get(section,
                                                'rabbit_notification_exchange')
            glance_cfg['topic'] = config.get(section,
                                             'rabbit_notification_topic')
            glance_cfg['datadir'] = config.get(section,
                                               'filesystem_store_datadir')

            return glance_cfg
        else:
            return None
    else:
        return None


def _connect(glance_cfg):
    conn = Connection('amqp://%s:%s@%s:%s//' % (glance_cfg['userid'],
                                                glance_cfg['password'],
                                                glance_cfg['host'],
                                                glance_cfg['port']))
    exchange = Exchange(glance_cfg['exchange'],
                        type='topic',
                        durable=False,
                        channel=conn.channel())

    return conn, exchange


def _declare_queue(glance_cfg, routing_key, conn, exchange):
    queue = Queue(name=routing_key,
                  routing_key=routing_key,
                  exchange=exchange,
                  channel=conn.channel(),
                  durable=False)
    queue.declare()

    return queue


def _duplicate_notifications(glance_cfg, api_nodes, conn, exchange):
    routing_key = '%s.info' % glance_cfg['topic']
    notification_queue = _declare_queue(glance_cfg,
                                        routing_key,
                                        conn,
                                        exchange)

    while True:
        msg = notification_queue.get()

        if msg is None:
            break

        for node in api_nodes:
            routing_key = 'glance_replicator.%s.info' % node
            node_queue = _declare_queue(glance_cfg,
                                        routing_key,
                                        conn,
                                        exchange)

            msg_new = exchange.Message(msg.body,
                                       content_type='application/json')
            exchange.publish(msg_new, routing_key)

        msg.ack()


def _sync_images(glance_cfg, conn, exchange):
    hostname = socket.gethostname()

    routing_key = 'glance_replicator.%s.info' % hostname
    queue = _declare_queue(glance_cfg, routing_key, conn, exchange)

    while True:
        msg = queue.get()

        if msg is None:
            break

        image_filename = "%s/%s" % (glance_cfg['datadir'],
                                    msg.payload['payload']['id'])

        if (msg.payload['event_type'] == 'image.update' and
            msg.payload['publisher_id'] != hostname):
            print 'Update detected on %s ...' % (image_filename)
            os.system("rsync -a -e 'ssh -o StrictHostKeyChecking=no' "
                      "root@%s:%s %s" % (msg.payload['publisher_id'],
                                         image_filename, image_filename))
            msg.ack()
        elif msg.payload['event_type'] == 'image.delete':
            print 'Delete detected on %s ...' % (image_filename)
            # don't delete file if it's still being copied
            image_glob = '%s/.*%s*' % (glance_cfg['datadir'],
                                       msg.payload['payload']['id'])
            if not glob.glob(image_glob):
                os.system('rm %s' % (image_filename))
                msg.ack()
        else:
            msg.ack()


def main(args):
    if len(args) == 2:
        cmd = args[1]
    else:
        sys.exit(1)

    if cmd in ('duplicate-notifications', 'sync-images', 'both'):
        glance_cfg = _read_glance_api_config()
        api_nodes = _read_api_nodes_config()

        if glance_cfg and api_nodes:
            conn, exchange = _connect(glance_cfg)
        else:
            sys.exit(1)
    else:
        sys.exit(1)

    if cmd == 'duplicate-notifications':
        _duplicate_notifications(glance_cfg, api_nodes, conn, exchange)
    elif cmd == 'sync-images':
        _sync_images(glance_cfg, conn, exchange)
    elif cmd == 'both':
        _duplicate_notifications(glance_cfg, api_nodes, conn, exchange)
        _sync_images(glance_cfg, conn, exchange)

    conn.close()


if __name__ == '__main__':
    main(sys.argv)

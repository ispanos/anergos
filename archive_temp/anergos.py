#!/usr/bin/env python3
# License: GNU GPLv3

import csv
import os
import sys

programsFolder = "programs/"
csvLists = ['arch.i3.csv']


class package:

    def __init__(self, nameInRepo, comment, repository):
        self.nameInRepo = nameInRepo
        self.repository = repository
        self.comment = comment


def mergeProgLists(folder, files):
    pkg_list = []
    for file in files:
        if os.path.exists(folder + file):
            with open(folder + file) as csvfile:
                readCSV = csv.reader(csvfile, delimiter=',')
                for row in readCSV:
                    if "#" not in row[0] and len(row[0]) > 0:
                        pkg_list.append(package(row[0], row[1], row[2]))
        else:
            print(file, "doesn't exist.", file=sys.stderr)
    return pkg_list


if __name__ == "__main__":

    # '''
    for i in mergeProgLists(programsFolder, csvLists):
        print('{} {} {}'.format(i.nameInRepo, i.comment, i.repository))
    # '''

import datetime

class orderService:
    def __init__(self, repo, items=[]):
        self.repo = repo
        self.items = items
        self.discount = 0

    def getItems(self):
        return self.items

    def AddItem(self, item):
        self.items.append(item)

    def paid(self):
        if self.discount > 0:
            return True
        else:
            return False

    def total(self, tax):
        t = 0
        for i in self.items:
            t = t + i["price"] * i["qty"]
        try:
            t = t - t * self.discount
            t = t + t * tax
        except:
            pass
        return t

    def save(self):
        try:
            self.repo.save(self.items)
        except Exception as e:
            print("error: " + str(e))
            return None
        return datetime.datetime.now()
